<cfoutput>
<!-- CBWIRE SCRIPTS -->
<!---
	WebSocket transport: install the fetch wrapper BEFORE livewire.js so
	sendRequest() hits the gated window.fetch. Only when transport is
	enabled AND SocketBox + supported host are available.
--->
<cfscript>
	transportEval = getTransportEvaluation();
	transportActive = transportEval.available;
	transportCfg = transportEval.clientConfig;
	transportCfg.updateUri = getUpdateEndpoint();
</cfscript>
<cfif transportActive>
<script data-navigate-once="true">
	window.__cbwireTransportConfig = #serializeJSON( transportCfg )#;
</script>
<script src="#moduleSettings.moduleRootURL#/includes/js/cbwire-websocket-transport.js" data-navigate-once="true"></script>
</cfif>
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
</cfoutput>
