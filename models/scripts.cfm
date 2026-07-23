<cfoutput>
<!-- CBWIRE SCRIPTS -->
<script src="#moduleSettings.moduleRootURL#/includes/js/livewire/dist/livewire.js?id=v3.6.4" <cfif not moduleSettings.showProgressBar>data-no-progress-bar</cfif> data-csrf="#generateCSRFToken()#" data-update-uri="#getUpdateEndpoint()#" data-navigate-once="true"></script>

<script data-navigate-once="true">
    document.addEventListener('livewire:init', () => {
        window.cbwire = window.Livewire;
        // Refire but as cbwire:init
        document.dispatchEvent( new CustomEvent( 'cbwire:init' ) );
    } );

    document.addEventListener('livewire:initialized', () => {
        // Refire but as cbwire:initialized
        document.dispatchEvent( new CustomEvent( 'cbwire:initialized' ) );
    } );

    document.addEventListener('livewire:navigated', () => { 
        // Refire but as cbwire:navigated
        document.dispatchEvent( new CustomEvent( 'cbwire:navigated' ) );
    } );
</script>

<!--- Custom client error handling: always present so per-wire overrides work when module is off --->
<cfif isDefined( "cehInjectClient" ) and cehInjectClient>
<script data-navigate-once="true" data-cbwire-custom-error-handling="true">
window.__CBWIRE_CEH = #serializeJSON( cehClientConfig )#;
document.addEventListener('cbwire:init', () => {
	if ( !window.cbwire || typeof cbwire.hook !== 'function' ) {
		return;
	}

	cbwire.hook('request', ({ payload, fail }) => {
		fail(({ status, content, preventDefault }) => {
			var cfg = window.__CBWIRE_CEH || {};
			var moduleOn = !!cfg.enabled;
			var clientLayerOn = cfg.clientEnabled !== false;
			var includeComponents = cfg.includeComponents !== false;
			var warnIfUnhandled = cfg.warnIfUnhandled !== false;

			// Parse request components and per-wire overrides from memo
			var components = [];
			var overrides = [];
			try {
				var body = typeof payload === 'string' ? JSON.parse( payload ) : payload;
				var list = ( body && body.components ) ? body.components : [];
				list.forEach( function( entry ) {
					var id = null;
					var name = null;
					var wireOverride = null;
					try {
						var snap = typeof entry.snapshot === 'string'
							? JSON.parse( entry.snapshot )
							: entry.snapshot;
						if ( snap && snap.memo ) {
							id = snap.memo.id || null;
							name = snap.memo.name || null;
							if ( typeof snap.memo.customErrorHandling === 'boolean' ) {
								wireOverride = snap.memo.customErrorHandling;
							}
						}
					} catch ( ignore ) {}
					overrides.push( wireOverride );
					components.push( { id: id, name: name, customErrorHandling: wireOverride } );
				} );
			} catch ( ignore ) {}

			// Feature on for a wire: override boolean, else module enabled
			function featureOn( wireOverride ) {
				if ( typeof wireOverride === 'boolean' ) {
					return wireOverride;
				}
				return moduleOn;
			}

			function clientOn( wireOverride ) {
				return featureOn( wireOverride ) && clientLayerOn;
			}

			// Any wire wanting client handling activates it for this request
			var useClient = false;
			if ( overrides.length ) {
				for ( var i = 0; i < overrides.length; i++ ) {
					if ( clientOn( overrides[ i ] ) ) {
						useClient = true;
						break;
					}
				}
			} else {
				useClient = clientOn( null );
			}

			if ( !useClient ) {
				return;
			}

			// Stop Livewire's failure modal and 419 confirm
			preventDefault();

			var type = 'http';
			if ( status === 503 && content === null ) {
				type = 'offline';
			} else if ( status === 419 ) {
				type = 'expired';
			}

			var message = null;
			var serverType = null;
			try {
				if ( content && typeof content === 'string' && content.charAt( 0 ) === '{' ) {
					var parsed = JSON.parse( content );
					if ( parsed && typeof parsed === 'object' ) {
						if ( parsed.message ) {
							message = parsed.message;
						}
						if ( parsed.type ) {
							serverType = parsed.type;
						}
					}
				}
			} catch ( ignore ) {}

			var detail = {
				type: type,
				status: status,
				content: content,
				message: message,
				serverType: serverType
			};
			if ( includeComponents ) {
				detail.components = components.map( function( c ) {
					return { id: c.id, name: c.name };
				} );
			}

			var errorEvent = new CustomEvent( 'cbwire:error', {
				detail: detail,
				cancelable: true
			} );
			document.dispatchEvent( errorEvent );

			if ( warnIfUnhandled && !errorEvent.defaultPrevented ) {
				console.warn(
					'CBWIRE custom error handling is enabled, but no listener marked cbwire:error as handled. The default error UI was suppressed.'
				);
			}
		} );
	} );
});
</script>
</cfif>
</cfoutput>
