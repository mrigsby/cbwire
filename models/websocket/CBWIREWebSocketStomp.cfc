/**
 * SocketBox STOMP listener that also accepts CBWIRE transport frames on the same endpoint.
 *
 * Use when the application already runs (or wants) SocketBox STOMP on /ws and also
 * enables CBWIRE WebSocket transport. Incoming text is inspected:
 *   - CBWIRE JSON { id, body }  → TransportService (Livewire update)
 *   - empty / STOMP frames      → super.onMessage (STOMP broker as usual)
 *
 * App root listener example:
 *   // WebSocket.cfc
 *   component extends="cbwire.models.websocket.CBWIREWebSocketStomp" {
 *       function configure() {
 *           return { heartBeatMS : 10000, subscriptions : {} };
 *       }
 *   }
 *
 * If you do not use STOMP, extend CBWIREWebSocket (Core) instead.
 *
 * Requires SocketBox. Host: CommandBox web.websocket.enable or BoxLang MiniServer.
 */
component extends="modules.socketbox.models.WebSocketSTOMP" {

	/**
	 * Demux CBWIRE transport frames vs STOMP (and empty PING frames).
	 *
	 * @message Raw text frame from the browser
	 * @channel SocketBox channel for this connection
	 */
	function onMessage( required string message, required any channel ) {
		try {
			var handler = getHandler();

			// Empty frame → STOMP heartbeat / PING (do not treat as CBWIRE)
			// STOMP command frames do not start with "{"; CBWIRE JSON does.
			if ( handler.isCBWIRETransportFrame( arguments.message ) ) {
				var reply = handler.handleTransportFrame( arguments.message );
				sendMessage( handler.serializeReply( reply ), arguments.channel );
				return;
			}

			// CONNECT, SEND, SUBSCRIBE, empty PING, heartbeats, etc.
			super.onMessage( argumentCollection = arguments );
		} catch ( any e ) {
			// If demux or CBWIRE handling failed unexpectedly, try not to kill STOMP path silently
			try {
				// Only emit CBWIRE-shaped error if this looked like JSON transport; else rethrow for STOMP
				if ( len( trim( arguments.message ) ) && left( trim( arguments.message ), 1 ) == "{" ) {
					sendMessage(
						serializeJSON( {
							"id"     : "",
							"status" : 500,
							"body"   : len( e.message ) ? e.message : "Unhandled WebSocket transport error"
						} ),
						arguments.channel
					);
					return;
				}
			} catch ( any sendErr ) {
				writeLog(
					text="CBWIRE STOMP WebSocket listener failed to reply: #sendErr.message# (original: #e.message#)",
					type="error",
					log="application"
				);
			}
			rethrow;
		}
	}

	/**
	 * Resolve the shared frame handler via WireBox when available.
	 */
	private any function getHandler() {
		var wirebox = resolveWireBox();
		return wirebox.getInstance( "CBWIREWebSocketHandler@cbwire" );
	}

	/**
	 * ColdBox application controller / wirebox references used by normal requests.
	 */
	private function resolveWireBox() {
		if ( structKeyExists( application, "cbController" ) ) {
			return application.cbController.getWireBox();
		}
		if ( structKeyExists( application, "wirebox" ) ) {
			return application.wirebox;
		}
		if ( structKeyExists( application, "cbBootstrap" ) ) {
			try {
				return application.cbBootstrap.getController().getWireBox();
			} catch ( any e ) {
				// fall through
			}
		}
		throw(
			type    = "CBWIRETransportException",
			message = "ColdBox WireBox is not available on the WebSocket request. Ensure the app is a ColdBox application and the WebSocket host preserves the application scope."
		);
	}

}
