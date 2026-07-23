/**
 * Resolves custom error handling settings, per-wire overrides,
 * compact server payloads, and client script config.
 */
component singleton {

	property name="moduleSettings" inject="coldbox:modulesettings:cbwire";
	property name="controller" inject="coldbox";
	property name="interceptorService" inject="coldbox:interceptorService";

	/**
	 * Normalized settings with defaults applied.
	 */
	function getConfig() {
		var raw = {};
		if ( structKeyExists( variables.moduleSettings, "customErrorHandling" )
			&& isStruct( variables.moduleSettings.customErrorHandling ) ) {
			raw = variables.moduleSettings.customErrorHandling;
		}

		return {
			"enabled"              : toBoolean( raw, "enabled", false ),
			"clientEnabled"        : toBoolean( raw, "clientEnabled", true ),
			"serverEnabled"        : toBoolean( raw, "serverEnabled", true ),
			"includeComponents"    : toBoolean( raw, "includeComponents", true ),
			"includeDetailInDev"   : toBoolean( raw, "includeDetailInDev", false ),
			"warnIfUnhandled"      : toBoolean( raw, "warnIfUnhandled", true ),
			"includeMessage"       : toBoolean( raw, "includeMessage", true ),
			"genericMessage"       : structKeyExists( raw, "genericMessage" ) && len( trim( toString( raw.genericMessage ) ) )
				? toString( raw.genericMessage )
				: "An error occurred while processing the request."
		};
	}

	/**
	 * Config object embedded in the client script.
	 */
	function getClientScriptConfig() {
		var cfg = getConfig();
		return {
			"enabled"           : cfg.enabled,
			"clientEnabled"     : cfg.clientEnabled,
			"includeComponents" : cfg.includeComponents,
			"warnIfUnhandled"   : cfg.warnIfUnhandled
		};
	}

	/**
	 * Always inject the client hook so per-wire overrides work
	 * even when the module master switch is off.
	 */
	function shouldInjectClientScript() {
		return true;
	}

	/**
	 * Effective master "on" for a wire.
	 * wireOverride: boolean true/false, or empty string / omitted for "no override".
	 * (Empty string is used instead of null for Adobe CF compatibility.)
	 */
	function isFeatureOnForWire( any wireOverride = "" ) {
		var cfg = getConfig();
		// Only a real boolean is a per-wire override
		if ( structKeyExists( arguments, "wireOverride" ) && isBoolean( arguments.wireOverride ) ) {
			return arguments.wireOverride ? true : false;
		}
		return cfg.enabled;
	}

	/**
	 * Effective client handling for a wire override value.
	 */
	function isClientEnabledForWire( any wireOverride = "" ) {
		var cfg = getConfig();
		return isFeatureOnForWire( argumentCollection = arguments ) && cfg.clientEnabled;
	}

	/**
	 * Effective server compact JSON for a wire override value.
	 */
	function isServerEnabledForWire( any wireOverride = "" ) {
		var cfg = getConfig();
		return isFeatureOnForWire( argumentCollection = arguments ) && cfg.serverEnabled;
	}

	/**
	 * True if any entry in wireOverrides enables the server layer.
	 * Empty array / no overrides: use module defaults only.
	 * Override entries: boolean true/false, or "" for no override.
	 */
	function isServerEnabledForRequest( array wireOverrides = [] ) {
		if ( !arrayLen( arguments.wireOverrides ) ) {
			return isServerEnabledForWire();
		}

		var anyOn = false;
		var sawOverrideOrDefault = false;

		for ( var item in arguments.wireOverrides ) {
			sawOverrideOrDefault = true;
			// Normalize null/undefined array slots to no-override
			var overrideVal = "";
			if ( !isNull( item ) && isBoolean( item ) ) {
				overrideVal = item ? true : false;
			}
			if ( isServerEnabledForWire( overrideVal ) ) {
				anyOn = true;
				break;
			}
		}

		return sawOverrideOrDefault ? anyOn : isServerEnabledForWire();
	}

	/**
	 * True if any component in the request should use client custom handling.
	 */
	function isClientEnabledForRequest( array wireOverrides = [] ) {
		if ( !arrayLen( arguments.wireOverrides ) ) {
			return isClientEnabledForWire();
		}

		for ( var item in arguments.wireOverrides ) {
			var overrideVal = "";
			if ( !isNull( item ) && isBoolean( item ) ) {
				overrideVal = item ? true : false;
			}
			if ( isClientEnabledForWire( overrideVal ) ) {
				return true;
			}
		}
		return false;
	}

	/**
	 * Extract per-wire customErrorHandling flags from an update request body.
	 * Returns array of boolean overrides, or "" for components with no override.
	 */
	function extractWireOverridesFromRequestContent( any content ) {
		var overrides = [];
		try {
			var body = isSimpleValue( arguments.content )
				? deserializeJSON( arguments.content )
				: arguments.content;
			if ( isNull( body ) || !isStruct( body ) || !structKeyExists( body, "components" ) || !isArray( body.components ) ) {
				return overrides;
			}
			for ( var entry in body.components ) {
				arrayAppend( overrides, extractOverrideFromComponentEntry( entry ) );
			}
		} catch ( any e ) {
			// ignore parse failures
		}
		return overrides;
	}

	/**
	 * From a single Livewire component payload entry, return boolean override or "" if none.
	 */
	function extractOverrideFromComponentEntry( any entry ) {
		try {
			if ( isNull( arguments.entry ) || !isStruct( arguments.entry ) || !structKeyExists( arguments.entry, "snapshot" ) ) {
				return "";
			}
			var snap = arguments.entry.snapshot;
			if ( isSimpleValue( snap ) ) {
				snap = deserializeJSON( snap );
			}
			if ( isStruct( snap ) && structKeyExists( snap, "memo" ) && isStruct( snap.memo )
				&& structKeyExists( snap.memo, "customErrorHandling" )
				&& isBoolean( snap.memo.customErrorHandling ) ) {
				return snap.memo.customErrorHandling ? true : false;
			}
		} catch ( any e ) {
			// ignore
		}
		return "";
	}

	/**
	 * Read override from a component instance (variables or this scope).
	 * Returns boolean or "" if not set.
	 */
	function getWireOverrideFromComponent( required any componentInstance ) {
		try {
			// Prefer variables.customErrorHandling (common CFML component property style)
			if ( structKeyExists( arguments.componentInstance, "customErrorHandling" )
				&& isBoolean( arguments.componentInstance.customErrorHandling ) ) {
				return arguments.componentInstance.customErrorHandling ? true : false;
			}
		} catch ( any e ) {
			// ignore
		}
		return "";
	}

	/**
	 * Build compact JSON struct for update failures.
	 */
	function buildCompactErrorPayload(
		required any error,
		required string type,
		required numeric status
	) {
		var cfg = getConfig();
		var publicMessage = cfg.genericMessage;

		if ( arguments.type == "expired" ) {
			publicMessage = "Page expired";
		} else if ( cfg.includeMessage ) {
			var rawMessage = trim( toString( arguments.error.message ?: "" ) );
			if ( len( rawMessage ) ) {
				publicMessage = left( rawMessage, 500 );
			}
		}

		var payload = {
			"error"         : true,
			"type"          : arguments.type,
			"status"        : arguments.status,
			"message"       : publicMessage,
			"exceptionType" : toString( arguments.error.type ?: "" )
		};

		if ( cfg.includeDetailInDev && isDevelopment() ) {
			payload[ "detail" ] = left( toString( arguments.error.detail ?: "" ), 1000 );
			if ( structKeyExists( arguments.error, "stackTrace" ) && !isNull( arguments.error.stackTrace ) ) {
				payload[ "stackTrace" ] = left( toString( arguments.error.stackTrace ), 2000 );
			}
		}

		return payload;
	}

	/**
	 * True when ColdBox environment is development.
	 */
	function isDevelopment() {
		try {
			return lCase( toString( variables.controller.getSetting( "environment" ) ) ) == "development";
		} catch ( any e ) {
			return false;
		}
	}

	/**
	 * Announce onCBWIREUpdateError after the compact payload is built.
	 * Interceptors may mutate interceptData.payload and interceptData.status.
	 * Failures in interceptors are swallowed so compact JSON is still returned.
	 *
	 * @return struct { payload, status, type }
	 */
	function announceUpdateError(
		required any event,
		required any error,
		required string type,
		required numeric status,
		required struct payload
	) {
		var result = {
			"payload" : arguments.payload,
			"status"  : arguments.status,
			"type"    : arguments.type
		};

		var interceptData = {
			"exception" : arguments.error,
			"type"      : arguments.type,
			"status"    : arguments.status,
			"payload"   : arguments.payload,
			"event"     : arguments.event
		};

		try {
			variables.interceptorService.announce( "onCBWIREUpdateError", interceptData );
		} catch ( any interceptError ) {
			// Never fall back to a full HTML error page because an interceptor failed
			try {
				writeLog(
					type = "error",
					text = "CBWIRE onCBWIREUpdateError interceptor failed: #interceptError.message#"
				);
			} catch ( any ignoreLog ) {
				// ignore logging failures
			}
			return result;
		}

		// Prefer mutated payload / status from interceptData (by reference or replaced)
		if ( structKeyExists( interceptData, "payload" ) && isStruct( interceptData.payload ) ) {
			result.payload = interceptData.payload;
		}
		if ( structKeyExists( interceptData, "status" ) && isNumeric( interceptData.status ) ) {
			result.status = val( interceptData.status );
			// Keep payload.status in sync when callers only change interceptData.status
			if ( isStruct( result.payload ) ) {
				result.payload[ "status" ] = result.status;
			}
		}
		if ( structKeyExists( interceptData, "type" ) && isSimpleValue( interceptData.type ) && len( interceptData.type ) ) {
			result.type = toString( interceptData.type );
			if ( isStruct( result.payload ) ) {
				result.payload[ "type" ] = result.type;
			}
		}

		return result;
	}

	/**
	 * Boolean setting helper.
	 */
	private boolean function toBoolean( required struct raw, required string key, required boolean defaultValue ) {
		if ( !structKeyExists( arguments.raw, arguments.key ) ) {
			return arguments.defaultValue;
		}
		if ( isBoolean( arguments.raw[ arguments.key ] ) ) {
			return arguments.raw[ arguments.key ] ? true : false;
		}
		return arguments.defaultValue;
	}

}
