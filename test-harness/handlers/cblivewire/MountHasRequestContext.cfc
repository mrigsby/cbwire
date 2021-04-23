component extends="cbLivewire.models.Component" accessors="true" {

    property name="message" default="Default value";

    function mount( event, rc, prc ) {
        var message = event.paramValue( "message", "Mounted value" );
        setMessage( event.getValue( "message" ) );
    }

    function renderIt() {
        return renderView( "_cblivewire/mount" );
    }
}