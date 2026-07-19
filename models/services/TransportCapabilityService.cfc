/**
 * Evaluates whether WebSocket transport can be used for this request/app.
 * Soft-requires SocketBox and a supported host (CommandBox or BoxLang MiniServer).
 * Never throws for missing optional pieces — callers fall back to HTTP.
 */
component singleton {

	property name="moduleSettings" inject="coldbox:modulesettings:cbwire";
	property name="moduleService"  inject="coldbox:moduleService";
	property name="log"            inject="logbox:logger:{this}";

	// Avoid spamming logs on every page render
	variables._unavailableLogged = false;

	/**
	 * Normalized transport settings (nested struct + legacy flat key).
	 */
	function getTransportSettings() {
		var defaults = {
			"enabled"      : false,
			"websocketUri" : "/ws",
			"timeoutMs"    : 5000,
			"debug"        : false
		};
		var settings = variables.moduleSettings;
		var transport = {};

		if ( settings.keyExists( "transport" ) && isStruct( settings.transport ) ) {
			transport = duplicate( settings.transport );
		}

		// Backward-compatible flat key (prefer nested transport.enabled)
		if ( settings.keyExists( "websocketTransport" ) && !transport.keyExists( "enabled" ) ) {
			transport.enabled = settings.websocketTransport;
		}

		structAppend( defaults, transport, true );
		return defaults;
	}

	/**
	 * Full availability evaluation for logging and client injection.
	 * Named evaluateTransport (not evaluate) to avoid CFML evaluate() BIF collision.
	 *
	 * @return struct { enabled, available, reasons[], settings, clientConfig }
	 */
	function evaluateTransport() {
		var transportSettings = getTransportSettings();
		var result = {
			"enabled"      : transportSettings.enabled ? true : false,
			"available"    : false,
			"reasons"      : [],
			"settings"     : transportSettings,
			"socketBox"    : false,
			"supportedHost": false
		};

		if ( !result.enabled ) {
			result.clientConfig = buildClientConfig( transportSettings, false );
			return result;
		}

		result.socketBox = isSocketBoxInstalled();
		if ( !result.socketBox ) {
			result.reasons.append(
				"SocketBox is not installed (run: box install socketbox)"
			);
		}

		result.supportedHost = isSupportedHost();
		if ( !result.supportedHost ) {
			result.reasons.append(
				"Host is not CommandBox or BoxLang MiniServer (WebSocket upgrade not available)"
			);
		}

		result.available = result.socketBox && result.supportedHost;
		result.clientConfig = buildClientConfig( transportSettings, result.available );

		if ( result.enabled && !result.available ) {
			logUnavailable( result.reasons );
		}

		return result;
	}

	/**
	 * True when transport should inject the client divert script.
	 */
	function isEffectivelyAvailable() {
		return evaluateTransport().available;
	}

	/**
	 * Detect SocketBox module without requiring it as a hard dependency.
	 */
	function isSocketBoxInstalled() {
		try {
			if ( variables.moduleService.isModuleRegistered( "socketbox" ) ) {
				return true;
			}
		} catch ( any e ) {
			// moduleService may not list inactive modules the same on all versions
		}

		// Filesystem fallbacks relative to common ColdBox layouts
		var candidates = [
			expandPath( "/modules/socketbox" ),
			expandPath( "/modules_app/socketbox" )
		];
		for ( var path in candidates ) {
			if ( len( path ) && directoryExists( path ) ) {
				return true;
			}
		}

		// Resolve core class if mapped
		try {
			createObject( "component", "modules.socketbox.models.WebSocketCore" );
			return true;
		} catch ( any e ) {
			// not installed / not mappable
		}

		return false;
	}

	/**
	 * CommandBox (any engine) or BoxLang MiniServer / BoxLang runtime.
	 * Does not prove web.websocket.enable is true on CommandBox — client falls back if /ws is down.
	 */
	function isSupportedHost() {
		var javaSystem = createObject( "java", "java.lang.System" );

		// Java system properties (when present)
		if ( len( javaSystem.getProperty( "commandbox.home", "" ) ) ) {
			return true;
		}
		if ( len( javaSystem.getProperty( "cfml.cli.home", "" ) ) ) {
			return true;
		}
		if ( len( javaSystem.getProperty( "boxlang.home", "" ) ) ) {
			return true;
		}

		// CommandBox embeds env vars into the CF process (reliable on Runwar)
		try {
			if ( server.keyExists( "system" ) && isStruct( server.system ) ) {
				if ( server.system.keyExists( "environment" ) && isStruct( server.system.environment ) ) {
					var env = server.system.environment;
					if ( structKeyExists( env, "COMMANDBOX_HOME" ) && len( env.COMMANDBOX_HOME ) ) {
						return true;
					}
					if ( structKeyExists( env, "COMMANDBOX_VERSION" ) && len( env.COMMANDBOX_VERSION ) ) {
						return true;
					}
					if ( structKeyExists( env, "BOXLANG_HOME" ) && len( env.BOXLANG_HOME ) ) {
						return true;
					}
				}
				if ( server.system.keyExists( "properties" ) && isStruct( server.system.properties ) ) {
					var props = server.system.properties;
					// Runwar is the CommandBox / Ortus embedded server
					if ( structKeyExists( props, "sun.java.command" ) && findNoCase( "runwar", props[ "sun.java.command" ] ) ) {
						return true;
					}
				}
			}
		} catch ( any e ) {
			// ignore detection errors
		}

		// BoxLang runtime / MiniServer markers
		if ( server.keyExists( "boxlang" ) ) {
			return true;
		}

		var productName = "";
		try {
			productName = server.coldfusion.productname ?: "";
		} catch ( any e ) {
			productName = "";
		}
		if ( findNoCase( "boxlang", productName ) ) {
			return true;
		}

		return false;
	}

	private function buildClientConfig( required struct transportSettings, required boolean available ) {
		return {
			"active"       : arguments.available,
			"updateUri"    : "", // filled by scripts.cfm / controller
			"websocketUri" : arguments.transportSettings.websocketUri,
			"timeoutMs"    : val( arguments.transportSettings.timeoutMs ),
			"debug"        : arguments.transportSettings.debug ? true : false
		};
	}

	private function logUnavailable( required array reasons ) {
		if ( variables._unavailableLogged ) {
			return;
		}
		variables._unavailableLogged = true;

		var message = "cbwire transport.enabled is true but WebSocket transport is unavailable. Falling back to HTTP. CBWIRE will continue to function normally. Reasons: "
			& arrayToList( arguments.reasons, "; " );

		try {
			variables.log.warn( message );
		} catch ( any e ) {
			// Logger may not resolve on all threads; writeLog is safer fallback
			writeLog( text=message, type="warning", log="application" );
		}
	}

}
