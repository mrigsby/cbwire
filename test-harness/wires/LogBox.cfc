component extends="cbwire.models.Component"{

    function mount(){
        log.debug( "Loaded mount()" );
    }

    function renderIt(){
        return renderView( "_wires/logbox" );
    }

}