/**
 * Shared handling for CBWIRE WebSocket transport frames.
 * Used by both the Core and STOMP SocketBox listeners so frame detection
 * and TransportService processing stay in one place.
 *
 * Protocol:
 *   inbound  { "id": n, "body": "<Livewire update JSON string>" }
 *   outbound { "id": n, "status": number, "body": "<response string>" }
 *
 * Does not extend SocketBox — safe to load without SocketBox installed.
 */
component singleton {

	property name="wirebox" inject="wirebox";
	property name="controller" inject="coldbox";

	/**
	 * True when the raw text looks like a CBWIRE transport JSON frame.
	 * Empty / whitespace → false (STOMP PING / ignore for Core empty handling).
	 * STOMP frames start with a command line (CONNECT, SEND, …), not "{".
	 *
	 * @message Raw WebSocket text frame
	 */
	boolean function isCBWIRETransportFrame( required string message ) {
		var text = trim( arguments.message );
		if ( !len( text ) ) {
			return false;
		}
		// STOMP commands are never JSON objects
		if ( left( text, 1 ) != "{" ) {
			return false;
		}

		try {
			var frame = deserializeJSON( text );
		} catch ( any e ) {
			return false;
		}

		if ( !isStruct( frame ) ) {
			return false;
		}
		if ( !structKeyExists( frame, "id" ) || isNull( frame.id ) ) {
			return false;
		}
		if ( isSimpleValue( frame.id ) && !len( toString( frame.id ) ) ) {
			return false;
		}
		if ( !structKeyExists( frame, "body" ) || isNull( frame.body ) ) {
			return false;
		}

		// Prefer Livewire-shaped body when it is JSON ( _token / components )
		var body = frame.body;
		if ( isSimpleValue( body ) ) {
			var bodyStr = trim( toString( body ) );
			if ( !len( bodyStr ) ) {
				return false;
			}
			if ( left( bodyStr, 1 ) == "{" ) {
				try {
					var payload = deserializeJSON( bodyStr );
					if ( isStruct( payload ) && (
						structKeyExists( payload, "components" ) ||
						structKeyExists( payload, "_token" )
					) ) {
						return true;
					}
					// JSON object body without Livewire keys — still treat as transport if id+body present
					return true;
				} catch ( any e ) {
					// body not JSON; still accept as opaque transport body
					return true;
				}
			}
			return true;
		}

		// body already a struct/array from client
		return true;
	}

	/**
	 * Process a CBWIRE transport frame and return the reply fields.
	 *
	 * @message Raw JSON frame text
	 * @return struct { id, status, body }
	 */
	struct function handleTransportFrame( required string message ) {
		var frameId = "";
		var text    = trim( arguments.message );

		if ( !len( text ) ) {
			return {
				"id"     : "",
				"status" : 400,
				"body"   : "Empty WebSocket message"
			};
		}

		var frame = {};
		try {
			frame = deserializeJSON( text );
		} catch ( any parseErr ) {
			return {
				"id"     : "",
				"status" : 400,
				"body"   : "Invalid JSON WebSocket frame"
			};
		}

		if ( !isStruct( frame ) ) {
			return {
				"id"     : "",
				"status" : 400,
				"body"   : "WebSocket frame must be a JSON object"
			};
		}

		frameId = frame.id ?: "";
		var body = frame.body ?: "";

		if ( isNull( frameId ) || ( isSimpleValue( frameId ) && !len( toString( frameId ) ) ) ) {
			return {
				"id"     : "",
				"status" : 400,
				"body"   : "Missing frame id"
			};
		}

		if ( isNull( body ) || ( isSimpleValue( body ) && !len( trim( toString( body ) ) ) ) ) {
			return {
				"id"     : frameId,
				"status" : 400,
				"body"   : "Missing frame body"
			};
		}

		if ( !isSimpleValue( body ) ) {
			body = serializeJSON( body );
		}

		var transportService = variables.wirebox.getInstance( "TransportService@cbwire" );
		var result = transportService.processUpdate( body );

		return {
			"id"     : frameId,
			"status" : result.status,
			"body"   : result.body
		};
	}

	/**
	 * Serialize a reply struct for sendMessage().
	 */
	string function serializeReply( required struct reply ) {
		return serializeJSON( {
			"id"     : arguments.reply.id,
			"status" : arguments.reply.status,
			"body"   : arguments.reply.body
		} );
	}

}
