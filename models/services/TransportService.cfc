/**
 * Shared WebSocket transport core: process a Livewire/CBWIRE update payload
 * via CBWIREController.handleRequest (direct path, no HTTP loopback).
 */
component singleton {

	property name="wirebox" inject="wirebox";
	property name="controller" inject="coldbox";
	property name="log" inject="logbox:logger:{this}";

	/**
	 * Process an update body string (same JSON Livewire POSTs to /cbwire/update).
	 *
	 * @body JSON string with _token and components
	 * @return struct { status: numeric, body: string }
	 */
	function processUpdate( required string body ) {
		if ( !len( trim( arguments.body ) ) ) {
			return {
				"status" : 400,
				"body"   : "Empty update body"
			};
		}

		// Reject non-JSON early (clear client error vs 500)
		try {
			deserializeJSON( arguments.body );
		} catch ( any parseErr ) {
			return {
				"status" : 400,
				"body"   : "Invalid JSON update body"
			};
		}

		var event = variables.controller.getRequestService().getContext();
		var cbwireController = variables.wirebox.getInstance( "CBWIREController@cbwire" );

		try {
			// Clear any prior stream flag so we can detect stream() during this update
			if ( event.privateValueExists( "_cbwire_stream" ) ) {
				event.setPrivateValue( "_cbwire_stream", false );
			}

			var result = cbwireController.handleRequest(
				{ "content" : arguments.body },
				event
			);

			// wire:stream wrote SSE-style output during handleRequest — not supported over framed WS.
			// Client should fall back to HTTP for streaming interactions; return a clear error status.
			if ( event.privateValueExists( "_cbwire_stream" ) && event.getPrivateValue( "_cbwire_stream" ) == true ) {
				return {
					"status" : 501,
					"body"   : "Streaming responses are not supported over WebSocket transport; use HTTP fetch"
				};
			}

			// handleRequest returns a struct; Livewire expects a JSON body string
			var bodyOut = isSimpleValue( result ) ? toString( result ) : serializeJSON( result );

			return {
				"status" : 200,
				"body"   : bodyOut
			};
		} catch ( any e ) {
			if ( isPageExpiredException( e ) ) {
				// Livewire client shows refresh prompt on HTTP 419
				return {
					"status" : 419,
					"body"   : len( e.message ) ? e.message : "Page expired."
				};
			}

			safeLogError( e );

			return {
				"status" : 500,
				"body"   : len( e.message ) ? e.message : "CBWIRE transport update failed"
			};
		}
	}

	/**
	 * True when CSRF / page-expiry path should surface as HTTP 419.
	 */
	private boolean function isPageExpiredException( required any exception ) {
		var message = arguments.exception.message ?: "";
		var type    = arguments.exception.type ?: "";

		if ( findNoCase( "Page expired", message ) ) {
			return true;
		}
		// CBWIREException with expired wording (operator-safe checks)
		if ( type == "CBWIREException" && findNoCase( "expired", message ) ) {
			return true;
		}
		return false;
	}

	/**
	 * Log without throwing if LogBox is unavailable on this thread.
	 */
	private function safeLogError( required any exception ) {
		var message = "CBWIRE WebSocket transport update failed: " & ( arguments.exception.message ?: "" );
		try {
			variables.log.error( message, arguments.exception );
		} catch ( any logErr ) {
			writeLog( text=message, type="error", log="application" );
		}
	}

}
