component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	function beforeAll() {
		super.beforeAll();
	}

	function run() {
		describe( "TransportService", function() {
			beforeEach( function() {
				setup();
			} );

			it( "should reject empty update body with 400", function() {
				var service = getInstance( "TransportService@cbwire" );
				var result  = service.processUpdate( "" );
				expect( result.status ).toBe( 400 );
				expect( result.body ).toInclude( "Empty" );
			} );

			it( "should reject invalid JSON body with 400", function() {
				var service = getInstance( "TransportService@cbwire" );
				var result  = service.processUpdate( "not-json{" );
				expect( result.status ).toBe( 400 );
				expect( result.body ).toInclude( "Invalid JSON" );
			} );

			it( "should map page expired errors to status 419", function() {
				var service = getInstance( "TransportService@cbwire" );
				// Force CSRF path: enable csrf and send a token that will fail verification
				var settings = getInstance( "coldbox:modulesettings:cbwire" );
				var originalCsrf = settings.csrfEnabled;
				settings.csrfEnabled = true;

				try {
					var fakePayload = serializeJSON( {
						"_token"     : "definitely-invalid-token-for-test",
						"components" : []
					} );

					var result = service.processUpdate( fakePayload );
					// Invalid CSRF throws CBWIREException "Page expired."
					expect( result.status ).toBe( 419 );
				} finally {
					settings.csrfEnabled = originalCsrf;
				}
			} );
		} );

		describe( "TransportCapabilityService", function() {
			beforeEach( function() {
				setup();
			} );

			it( "should report unavailable when transport.enabled is false (default)", function() {
				var settings = getInstance( "coldbox:modulesettings:cbwire" );
				var originalTransport = duplicate( settings.transport ?: { enabled: false } );
				settings.transport = { enabled: false };

				try {
					var capability = getInstance( "TransportCapabilityService@cbwire" );
					var evaluation = capability.evaluateTransport();
					expect( evaluation.enabled ).toBeFalse();
					expect( evaluation.available ).toBeFalse();
				} finally {
					settings.transport = originalTransport;
				}
			} );

			it( "should expose socketBox and supportedHost flags when enabled", function() {
				var settings = getInstance( "coldbox:modulesettings:cbwire" );
				var originalTransport = duplicate( settings.transport ?: { enabled: false } );
				settings.transport = { enabled: true };

				try {
					var capability = getInstance( "TransportCapabilityService@cbwire" );
					var evaluation = capability.evaluateTransport();
					expect( evaluation.enabled ).toBeTrue();
					expect( evaluation ).toHaveKey( "socketBox" );
					expect( evaluation ).toHaveKey( "supportedHost" );
					expect( evaluation ).toHaveKey( "clientConfig" );
					expect( evaluation.clientConfig ).toHaveKey( "active" );
				} finally {
					settings.transport = originalTransport;
				}
			} );

			it( "should detect SocketBox when installed in the harness", function() {
				var capability = getInstance( "TransportCapabilityService@cbwire" );
				// Harness depends on socketbox — should resolve true on this environment
				expect( capability.isSocketBoxInstalled() ).toBeTrue();
			} );

			it( "should detect CommandBox-style supported host in this harness", function() {
				var capability = getInstance( "TransportCapabilityService@cbwire" );
				expect( capability.isSupportedHost() ).toBeTrue();
			} );

			it( "should become effectively available when transport is enabled on a supported host", function() {
				var settings = getInstance( "coldbox:modulesettings:cbwire" );
				var originalTransport = duplicate( settings.transport ?: { enabled: false } );
				settings.transport = { enabled: true };

				try {
					var capability = getInstance( "TransportCapabilityService@cbwire" );
					// Harness has SocketBox + CommandBox WS host
					expect( capability.isEffectivelyAvailable() ).toBeTrue();
				} finally {
					settings.transport = originalTransport;
				}
			} );
		} );
	}

}
