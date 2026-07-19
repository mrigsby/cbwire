/**
 * SocketBox Core listener for CBWIRE update frames.
 *
 * Use when the app does not run SocketBox STOMP on the same WebSocket endpoint.
 *
 * App root listener example:
 *   // WebSocket.cfc
 *   component extends="cbwire.models.websocket.CBWIREWebSocket" {}
 *
 * Or point CommandBox web.websocket.listener at this CFC under the module path.
 *
 * For STOMP + CBWIRE on the same /ws endpoint, use CBWIREWebSocketStomp instead.
 *
 * Requires SocketBox and a host that upgrades WebSockets (CommandBox with
 * web.websocket.enable or BoxLang MiniServer).
 *
 * Protocol:
 *   inbound  { "id": n, "body": "<json string>" }
 *   outbound { "id": n, "status": 200|400|419|500|501, "body": "<json or message>" }
 */
component extends="modules.socketbox.models.WebSocketCore" {

	/**
	 * Handle an inbound text frame as a CBWIRE transport request.
	 *
	 * @message Raw text frame from the browser
	 * @channel SocketBox channel for this connection
	 */
	function onMessage( required string message, required any channel ) {
		try {
			var handler = getHandler();
			// Core-only path: empty message is invalid for CBWIRE (STOMP uses empty for PING)
			if ( !len( trim( arguments.message ) ) ) {
				sendMessage(
					handler.serializeReply( {
						"id"     : "",
						"status" : 400,
						"body"   : "Empty WebSocket message"
					} ),
					arguments.channel
				);
				return;
			}

			var reply = handler.handleTransportFrame( arguments.message );
			sendMessage( handler.serializeReply( reply ), arguments.channel );
		} catch ( any e ) {
			try {
				sendMessage(
					serializeJSON( {
						"id"     : "",
						"status" : 500,
						"body"   : len( e.message ) ? e.message : "Unhandled WebSocket transport error"
					} ),
					arguments.channel
				);
			} catch ( any sendErr ) {
				writeLog(
					text="CBWIRE WebSocket listener failed to reply: #sendErr.message# (original: #e.message#)",
					type="error",
					log="application"
				);
			}
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
