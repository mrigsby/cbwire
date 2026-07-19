/**
 * CBWIRE WebSocket transport client.
 *
 * Gates Livewire/CBWIRE component update fetch calls. When a WebSocket to the
 * configured URI is open, sends the same JSON body as the HTTP update and
 * returns a native Response. On closed socket, timeout, or error, falls back
 * to native fetch so the UI keeps working.
 *
 * Concurrent updates are correlated by frame id. While the socket is
 * connecting, requests wait briefly for OPEN instead of all falling to HTTP.
 * Reconnect uses exponential backoff after unexpected close.
 *
 * wire:stream / server-sent stream responses are not supported over this
 * transport; those updates should continue to use HTTP (no X-Livewire-Stream
 * on synthetic Responses). Streaming still works if the socket is down and
 * fetch is used, or when transport is disabled.
 *
 * Must load BEFORE livewire.js. Injected only when transport is effectively
 * available (module setting + SocketBox + supported host).
 *
 * Config (set before this file loads):
 *   window.__cbwireTransportConfig = {
 *     active       : true,
 *     updateUri    : "/cbwire/update",
 *     websocketUri : "/ws",
 *     timeoutMs    : 5000,
 *     debug        : false
 *   }
 */
( function () {
	"use strict";

	if ( window.__cbwireWsTransport && window.__cbwireWsTransport.installed ) {
		return;
	}

	var config = window.__cbwireTransportConfig || {};
	var updateUri = String( config.updateUri || "/cbwire/update" );
	var websocketUri = String( config.websocketUri || "/ws" );
	var timeoutMs = parseInt( config.timeoutMs, 10 );
	if ( isNaN( timeoutMs ) || timeoutMs < 1 ) {
		timeoutMs = 5000;
	}
	var debug = !!config.debug;
	var active = config.active !== false;

	// Wait for CONNECTING → OPEN before falling back to HTTP (first-load race)
	var connectWaitMs = Math.min( 1500, timeoutMs );

	var realFetch = window.fetch.bind( window );
	var socket = null;
	var pending = new Map();
	var seq = 0;

	// Reconnect backoff
	var reconnectAttempt = 0;
	var reconnectTimer = null;
	var maxReconnectDelayMs = 30000;
	var intentionalClose = false;

	// Resolvers waiting for OPEN while status is CONNECTING
	var openWaiters = [];

	var stats = {
		installed       : true,
		active          : active,
		updateUri       : updateUri,
		websocketUri    : websocketUri,
		timeoutMs       : timeoutMs,
		intercepted     : 0,
		viaWebSocket    : 0,
		viaHttp         : 0,
		passedThrough   : 0,
		reconnects      : 0,
		pendingCount    : 0,
		lastError       : null,
		readyState      : function () {
			return socket ? socket.readyState : -1;
		}
	};

	function urlFromInput( input ) {
		if ( typeof input === "string" ) {
			return input;
		}
		if ( input && typeof input.url === "string" ) {
			return input.url;
		}
		if ( input && typeof input.href === "string" ) {
			return input.href;
		}
		return String( input );
	}

	function getHeaderMap( input, init ) {
		var map = {};

		function add( name, value ) {
			if ( name == null ) {
				return;
			}
			map[ String( name ).toLowerCase() ] = value;
		}

		var headers = ( init && init.headers ) || null;

		if ( !headers && input && typeof input.headers !== "undefined" && input.headers ) {
			headers = input.headers;
		}

		if ( !headers ) {
			return map;
		}

		if ( typeof headers.forEach === "function" ) {
			headers.forEach( function ( value, name ) {
				add( name, value );
			} );
			return map;
		}

		if ( Array.isArray( headers ) ) {
			headers.forEach( function ( pair ) {
				if ( pair && pair.length >= 2 ) {
					add( pair[ 0 ], pair[ 1 ] );
				}
			} );
			return map;
		}

		if ( typeof headers === "object" ) {
			Object.keys( headers ).forEach( function ( name ) {
				add( name, headers[ name ] );
			} );
		}

		return map;
	}

	function isWireUpdate( input, init ) {
		var url = urlFromInput( input );
		var headerMap = getHeaderMap( input, init );

		if ( "x-livewire-navigate" in headerMap ) {
			return false;
		}

		// Event-stream / stream responses are HTTP-only for this transport
		if ( "accept" in headerMap && String( headerMap.accept ).indexOf( "text/event-stream" ) !== -1 ) {
			return false;
		}

		if ( !( "x-livewire" in headerMap ) ) {
			return false;
		}

		return url.indexOf( updateUri ) !== -1;
	}

	function log() {
		if ( !debug ) {
			return;
		}
		var args = Array.prototype.slice.call( arguments );
		args.unshift( "[cbwire-ws-transport]" );
		// eslint-disable-next-line no-console
		console.debug.apply( console, args );
	}

	function buildWsUrl() {
		var proto = location.protocol === "https:" ? "wss:" : "ws:";
		var path = websocketUri.charAt( 0 ) === "/" ? websocketUri : "/" + websocketUri;
		return proto + "//" + location.host + path;
	}

	function updatePendingCount() {
		stats.pendingCount = pending.size;
	}

	function settlePending( id, response, error ) {
		var entry = pending.get( id );
		if ( !entry ) {
			return;
		}
		pending.delete( id );
		updatePendingCount();
		clearTimeout( entry.timer );
		if ( error ) {
			entry.reject( error );
		} else {
			entry.resolve( response );
		}
	}

	function fallbackPendingToHttp( reason ) {
		var entries = [];
		pending.forEach( function ( entry, id ) {
			entries.push( { id: id, entry: entry } );
		} );
		entries.forEach( function ( item ) {
			pending.delete( item.id );
			clearTimeout( item.entry.timer );
			stats.viaHttp++;
			log( "http fallback", { id: item.id, reason: reason } );
			realFetch( item.entry.input, item.entry.init ).then( item.entry.resolve, item.entry.reject );
		} );
		updatePendingCount();
	}

	function flushOpenWaiters( ok ) {
		var waiters = openWaiters.slice();
		openWaiters.length = 0;
		waiters.forEach( function ( w ) {
			clearTimeout( w.timer );
			w.resolve( ok );
		} );
	}

	function scheduleReconnect() {
		if ( intentionalClose || !active ) {
			return;
		}
		if ( reconnectTimer ) {
			return;
		}
		var delay = Math.min(
			maxReconnectDelayMs,
			500 * Math.pow( 2, reconnectAttempt )
		);
		// jitter ±20%
		delay = Math.floor( delay * ( 0.8 + Math.random() * 0.4 ) );
		reconnectAttempt++;
		stats.reconnects++;
		log( "reconnect scheduled", { attempt: reconnectAttempt, delayMs: delay } );
		reconnectTimer = setTimeout( function () {
			reconnectTimer = null;
			ensureSocket( true );
		}, delay );
	}

	function onSocketMessage( event ) {
		var frame;
		try {
			frame = JSON.parse( event.data );
		} catch ( e ) {
			log( "invalid frame", event.data );
			stats.lastError = "invalid_frame";
			return;
		}

		var id = frame.id;
		// Coerce string ids from some serializers
		if ( typeof id === "string" && /^\d+$/.test( id ) ) {
			id = parseInt( id, 10 );
		}
		if ( id == null || !pending.has( id ) ) {
			log( "unmatched frame id", id );
			return;
		}

		var status = typeof frame.status === "number" ? frame.status : parseInt( frame.status, 10 );
		if ( isNaN( status ) ) {
			status = 200;
		}

		var body = frame.body;
		if ( body != null && typeof body !== "string" ) {
			body = JSON.stringify( body );
		}
		if ( body == null ) {
			body = "";
		}

		// Native Response: Livewire handles 419 via response.status / !ok
		var response = new Response( body, {
			status : status,
			headers: {
				"Content-Type": "application/json"
			}
		} );

		stats.viaWebSocket++;
		log( "ws response", { id: id, status: status } );
		settlePending( id, response, null );
	}

	function onSocketOpen() {
		log( "socket open" );
		reconnectAttempt = 0;
		flushOpenWaiters( true );
	}

	function onSocketClose( ev ) {
		log( "socket closed", ev && ev.code );
		socket = null;
		flushOpenWaiters( false );
		// In-flight updates: fail open to HTTP so UI recovers
		fallbackPendingToHttp( "socket_closed" );
		if ( !intentionalClose ) {
			scheduleReconnect();
		}
	}

	function onSocketError() {
		log( "socket error" );
		stats.lastError = "socket_error";
	}

	function ensureSocket( isReconnect ) {
		if ( socket && ( socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING ) ) {
			return socket;
		}

		try {
			intentionalClose = false;
			socket = new WebSocket( buildWsUrl() );
			socket.addEventListener( "open", onSocketOpen );
			socket.addEventListener( "message", onSocketMessage );
			socket.addEventListener( "close", onSocketClose );
			socket.addEventListener( "error", onSocketError );
			log( isReconnect ? "reconnecting" : "connecting", buildWsUrl() );
		} catch ( e ) {
			log( "socket construct failed", e );
			stats.lastError = String( e && e.message ? e.message : e );
			socket = null;
			scheduleReconnect();
		}

		return socket;
	}

	/**
	 * Resolve when socket is OPEN, or false if not within waitMs.
	 */
	function waitForOpen( waitMs ) {
		if ( socket && socket.readyState === WebSocket.OPEN ) {
			return Promise.resolve( true );
		}
		if ( !socket || socket.readyState !== WebSocket.CONNECTING ) {
			return Promise.resolve( false );
		}
		return new Promise( function ( resolve ) {
			var timer = setTimeout( function () {
				var idx = openWaiters.indexOf( waiter );
				if ( idx !== -1 ) {
					openWaiters.splice( idx, 1 );
				}
				resolve( !!( socket && socket.readyState === WebSocket.OPEN ) );
			}, waitMs );
			var waiter = { resolve: resolve, timer: timer };
			openWaiters.push( waiter );
		} );
	}

	function bodyFromInit( input, init ) {
		if ( init && typeof init.body === "string" ) {
			return init.body;
		}
		if ( input && typeof input === "object" && typeof input.text === "function" ) {
			// Request object — rare for Livewire; fall back to HTTP
			return null;
		}
		return init && init.body != null ? String( init.body ) : "";
	}

	function sendOverSocket( id, body, input, init ) {
		return new Promise( function ( resolve, reject ) {
			var timer = setTimeout( function () {
				if ( !pending.has( id ) ) {
					return;
				}
				pending.delete( id );
				updatePendingCount();
				stats.viaHttp++;
				log( "http fallback (timeout)", { id: id } );
				realFetch( input, init ).then( resolve, reject );
			}, timeoutMs );

			pending.set( id, {
				resolve: resolve,
				reject : reject,
				timer  : timer,
				input  : input,
				init   : init
			} );
			updatePendingCount();

			try {
				socket.send( JSON.stringify( { id: id, body: body } ) );
				log( "ws send", { id: id, pending: pending.size } );
			} catch ( e ) {
				pending.delete( id );
				updatePendingCount();
				clearTimeout( timer );
				stats.viaHttp++;
				stats.lastError = String( e && e.message ? e.message : e );
				log( "ws send failed", e );
				realFetch( input, init ).then( resolve, reject );
			}
		} );
	}

	function transportFetch( input, init ) {
		stats.intercepted++;

		if ( !active ) {
			stats.viaHttp++;
			return realFetch( input, init );
		}

		var body = bodyFromInit( input, init );
		if ( body === null ) {
			stats.viaHttp++;
			return realFetch( input, init );
		}

		var ws = ensureSocket( false );

		// Already open — send immediately (supports concurrent ids)
		if ( ws && ws.readyState === WebSocket.OPEN ) {
			var idOpen = ++seq;
			return sendOverSocket( idOpen, body, input, init );
		}

		// Connecting — wait briefly so concurrent boot updates can share one socket
		if ( ws && ws.readyState === WebSocket.CONNECTING ) {
			return waitForOpen( connectWaitMs ).then( function ( opened ) {
				if ( opened && socket && socket.readyState === WebSocket.OPEN ) {
					var idWait = ++seq;
					return sendOverSocket( idWait, body, input, init );
				}
				stats.viaHttp++;
				log( "http fallback (connect wait elapsed)" );
				return realFetch( input, init );
			} );
		}

		// Down — HTTP now; reconnect scheduled from close/error
		stats.viaHttp++;
		log( "http fallback (socket not open)" );
		return realFetch( input, init );
	}

	window.fetch = function ( input, init ) {
		if ( !isWireUpdate( input, init ) ) {
			stats.passedThrough++;
			return realFetch( input, init );
		}
		return transportFetch( input, init );
	};

	window.__cbwireWsTransport = stats;

	if ( active ) {
		ensureSocket( false );
	}

	log( "installed", {
		active       : active,
		updateUri    : updateUri,
		websocketUri : websocketUri,
		timeoutMs    : timeoutMs
	} );
} )();
