component {

	property name="cbwireController" inject="CBWIREController@cbwire";
	property name="moduleSettings" inject="coldbox:modulesettings:cbwire";
	property name="customErrorHandlingService" inject="CustomErrorHandlingService@cbwire";

	/**
	 * Primary entry point for cbwire requests.
	 *
	 * URI: /cbwire/update
	 */
	function index( event, rc, prc ){
		try {
			return cbwireController.handleRequest( getHTTPRequestData(), arguments.event );
		} catch ( any e ) {
			var httpData = getHTTPRequestData();
			var useCompact = shouldUseCompactServerErrors( httpData );

			// Session / CSRF page expired
			if ( e.message contains "Page expired" ) {
				if ( useCompact ) {
					return renderCompactUpdateError(
						event  = arguments.event,
						error  = e,
						type   = "expired",
						status = 419,
						statusText = "Page Expired"
					);
				}
				event.noLayout();
				event.setView( view="errors/pageExpired", module="cbwire" );
				event.setHTTPHeader( statusCode="419", statusText="Page Expired" );
				return;
			}

			// Other failures: optional compact JSON instead of a full error page
			if ( useCompact ) {
				return renderCompactUpdateError(
					event  = arguments.event,
					error  = e,
					type   = "server",
					status = 500,
					statusText = "Internal Server Error"
				);
			}

			rethrow;
		}
	}

	/**
	 * Endpoint for file uploads
	 *
	 * URI: /cbwire/upload-file
	 */
	function uploadFile( event, rc, prc ) {
		return cbwireController.handleFileUpload( getHTTPRequestData(), event );
	}

	/**
	 * Endpoint for previewing file uploads
	 *
	 * URI: /cbwire/preview-file/:uploadUUID
	 */
	function previewFile( event, rc, prc ) {
		return cbwireController.handleFilePreview( getHTTPRequestData(), event );
	}

	/**
	 * Server compact JSON when module/server layer is on for this request,
	 * including per-wire overrides from the request body when present.
	 */
	private boolean function shouldUseCompactServerErrors( required struct httpData ) {
		var content = "";
		if ( structKeyExists( arguments.httpData, "content" ) ) {
			content = arguments.httpData.content;
		}
		var overrides = variables.customErrorHandlingService.extractWireOverridesFromRequestContent( content );
		return variables.customErrorHandlingService.isServerEnabledForRequest( overrides );
	}

	/**
	 * Returns a small JSON body for Livewire update failures.
	 * Fires onCBWIREUpdateError so apps can log or adjust the payload.
	 */
	private any function renderCompactUpdateError(
		required any event,
		required any error,
		required string type,
		required numeric status,
		string statusText = ""
	) {
		var payload = variables.customErrorHandlingService.buildCompactErrorPayload(
			error  = arguments.error,
			type   = arguments.type,
			status = arguments.status
		);

		var announced = variables.customErrorHandlingService.announceUpdateError(
			event   = arguments.event,
			error   = arguments.error,
			type    = arguments.type,
			status  = arguments.status,
			payload = payload
		);

		var finalStatus = announced.status;
		var finalPayload = announced.payload;
		var finalStatusText = len( arguments.statusText ) ? arguments.statusText : "Error";
		if ( finalStatus == 419 ) {
			finalStatusText = "Page Expired";
		} else if ( finalStatus == 500 && !len( arguments.statusText ) ) {
			finalStatusText = "Internal Server Error";
		}

		return arguments.event.renderData(
			type       = "json",
			data       = finalPayload,
			statusCode = finalStatus,
			statusText = finalStatusText
		);
	}

}
