component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	function beforeAll() {
		super.beforeAll();
	}

	function run() {
		describe( "CBWIREWebSocketHandler", function() {
			beforeEach( function() {
				setup();
			} );

			it( "should not treat empty messages as CBWIRE frames (STOMP PING)", function() {
				var handler = getInstance( "CBWIREWebSocketHandler@cbwire" );
				expect( handler.isCBWIRETransportFrame( "" ) ).toBeFalse();
				expect( handler.isCBWIRETransportFrame( "   " ) ).toBeFalse();
			} );

			it( "should not treat STOMP command frames as CBWIRE frames", function() {
				var handler = getInstance( "CBWIREWebSocketHandler@cbwire" );
				var stompConnect = "CONNECT" & chr( 10 ) & "login:user" & chr( 10 ) & chr( 10 ) & chr( 0 );
				expect( handler.isCBWIRETransportFrame( stompConnect ) ).toBeFalse();
				expect( handler.isCBWIRETransportFrame( "SEND" & chr( 10 ) & "destination:/topic/x" & chr( 10 ) & chr( 10 ) & "{}" & chr( 0 ) ) ).toBeFalse();
			} );

			it( "should recognize CBWIRE JSON transport frames", function() {
				var handler = getInstance( "CBWIREWebSocketHandler@cbwire" );
				var frame = serializeJSON( {
					"id"   : 1,
					"body" : serializeJSON( { "_token" : "abc", "components" : [] } )
				} );
				expect( handler.isCBWIRETransportFrame( frame ) ).toBeTrue();
			} );

			it( "should return 400 for empty body on handleTransportFrame", function() {
				var handler = getInstance( "CBWIREWebSocketHandler@cbwire" );
				var result  = handler.handleTransportFrame( "" );
				expect( result.status ).toBe( 400 );
			} );

			it( "should return 400 for invalid JSON on handleTransportFrame", function() {
				var handler = getInstance( "CBWIREWebSocketHandler@cbwire" );
				var result  = handler.handleTransportFrame( "{not-json" );
				expect( result.status ).toBe( 400 );
			} );

			it( "should map CSRF failure to 419 for a valid-shaped transport frame", function() {
				var handler  = getInstance( "CBWIREWebSocketHandler@cbwire" );
				var settings = getInstance( "coldbox:modulesettings:cbwire" );
				var originalCsrf = settings.csrfEnabled;
				settings.csrfEnabled = true;

				try {
					var frame = serializeJSON( {
						"id"   : 42,
						"body" : serializeJSON( {
							"_token"     : "invalid-token-for-test",
							"components" : []
						} )
					} );
					var result = handler.handleTransportFrame( frame );
					expect( result.id ).toBe( 42 );
					expect( result.status ).toBe( 419 );
				} finally {
					settings.csrfEnabled = originalCsrf;
				}
			} );
		} );
	}

}
