component extends="coldbox.system.testing.BaseTestCase" {

	function beforeAll() {
		super.beforeAll();
	}

	function run() {
		describe( "CustomErrorHandlingService", function() {

			beforeEach( function() {
				setup();
				service = getInstance( "CustomErrorHandlingService@cbwire" );
				settings = getInstance( "coldbox:modulesettings:cbwire" );
				// Full defaults baseline for each spec
				settings.customErrorHandling = {
					"enabled"            : false,
					"clientEnabled"      : true,
					"serverEnabled"      : true,
					"includeComponents"  : true,
					"includeDetailInDev" : false,
					"warnIfUnhandled"    : true,
					"includeMessage"     : true,
					"genericMessage"     : "An error occurred while processing the request."
				};
			} );

			it( "applies default config values", function() {
				var cfg = service.getConfig();
				expect( cfg.enabled ).toBeFalse();
				expect( cfg.clientEnabled ).toBeTrue();
				expect( cfg.serverEnabled ).toBeTrue();
				expect( cfg.includeComponents ).toBeTrue();
				expect( cfg.includeDetailInDev ).toBeFalse();
				expect( cfg.warnIfUnhandled ).toBeTrue();
				expect( cfg.includeMessage ).toBeTrue();
				expect( cfg.genericMessage ).toInclude( "error occurred" );
			} );

			it( "uses module enabled for wire when no override", function() {
				expect( service.isFeatureOnForWire() ).toBeFalse();
				expect( service.isFeatureOnForWire( "" ) ).toBeFalse();
				settings.customErrorHandling.enabled = true;
				expect( service.isFeatureOnForWire() ).toBeTrue();
				expect( service.isFeatureOnForWire( "" ) ).toBeTrue();
			} );

			it( "allows per-wire true when module enabled is false", function() {
				settings.customErrorHandling.enabled = false;
				expect( service.isClientEnabledForWire( true ) ).toBeTrue();
				expect( service.isServerEnabledForWire( true ) ).toBeTrue();
			} );

			it( "allows per-wire false when module enabled is true", function() {
				settings.customErrorHandling.enabled = true;
				expect( service.isClientEnabledForWire( false ) ).toBeFalse();
				expect( service.isServerEnabledForWire( false ) ).toBeFalse();
			} );

			it( "respects clientEnabled and serverEnabled layer flags", function() {
				settings.customErrorHandling.enabled = true;
				settings.customErrorHandling.clientEnabled = false;
				settings.customErrorHandling.serverEnabled = true;
				expect( service.isClientEnabledForWire() ).toBeFalse();
				expect( service.isServerEnabledForWire() ).toBeTrue();

				settings.customErrorHandling.clientEnabled = true;
				settings.customErrorHandling.serverEnabled = false;
				expect( service.isClientEnabledForWire( true ) ).toBeTrue();
				expect( service.isServerEnabledForWire( true ) ).toBeFalse();
			} );

			it( "enables server for request when any wire override is on", function() {
				settings.customErrorHandling.enabled = false;
				expect( service.isServerEnabledForRequest( [ false, true ] ) ).toBeTrue();
				expect( service.isServerEnabledForRequest( [ false, false ] ) ).toBeFalse();
			} );

			it( "enables client for request when any wire override is on", function() {
				settings.customErrorHandling.enabled = false;
				expect( service.isClientEnabledForRequest( [ false, true ] ) ).toBeTrue();
				expect( service.isClientEnabledForRequest( [ false ] ) ).toBeFalse();
			} );

			it( "extracts wire overrides from request content snapshots", function() {
				var body = {
					"components" : [
						{
							"snapshot" : serializeJSON( {
								"memo" : { "id" : "a", "name" : "One", "customErrorHandling" : true },
								"data" : {}
							} )
						},
						{
							"snapshot" : serializeJSON( {
								"memo" : { "id" : "b", "name" : "Two" },
								"data" : {}
							} )
						}
					]
				};
				var overrides = service.extractWireOverridesFromRequestContent( serializeJSON( body ) );
				expect( overrides.len() ).toBe( 2 );
				expect( overrides[ 1 ] ).toBeTrue();
				// "" sentinel = no override (Adobe-safe; not null)
				expect( isBoolean( overrides[ 2 ] ) ).toBeFalse();
				expect( overrides[ 2 ] ).toBe( "" );
			} );

			it( "builds compact payload with exception message when includeMessage is true", function() {
				settings.customErrorHandling.includeMessage = true;
				var payload = service.buildCompactErrorPayload(
					error  = { message : "Secret failed", type : "DemoError", detail : "x" },
					type   = "server",
					status = 500
				);
				expect( payload.error ).toBeTrue();
				expect( payload.type ).toBe( "server" );
				expect( payload.message ).toBe( "Secret failed" );
				expect( payload.exceptionType ).toBe( "DemoError" );
				expect( payload ).notToHaveKey( "detail" );
			} );

			it( "uses genericMessage when includeMessage is false", function() {
				settings.customErrorHandling.includeMessage = false;
				settings.customErrorHandling.genericMessage = "Please try again later.";
				var payload = service.buildCompactErrorPayload(
					error  = { message : "Secret failed", type : "DemoError" },
					type   = "server",
					status = 500
				);
				expect( payload.message ).toBe( "Please try again later." );
			} );

			it( "uses Page expired message for expired type", function() {
				var payload = service.buildCompactErrorPayload(
					error  = { message : "Page expired.", type : "CBWIREException" },
					type   = "expired",
					status = 419
				);
				expect( payload.type ).toBe( "expired" );
				expect( payload.message ).toBe( "Page expired" );
			} );

			it( "includes detail in payload when includeDetailInDev and development", function() {
				settings.customErrorHandling.includeDetailInDev = true;
				prepareMock( service ).$( "isDevelopment", true );
				var payload = service.buildCompactErrorPayload(
					error  = {
						message    : "Boom",
						type       : "DemoError",
						detail     : "More info",
						stackTrace : "line1"
					},
					type   = "server",
					status = 500
				);
				expect( payload ).toHaveKey( "detail" );
				expect( payload.detail ).toBe( "More info" );
				expect( payload ).toHaveKey( "stackTrace" );
			} );

			it( "omits detail when not development even if includeDetailInDev", function() {
				settings.customErrorHandling.includeDetailInDev = true;
				prepareMock( service ).$( "isDevelopment", false );
				var payload = service.buildCompactErrorPayload(
					error  = { message : "Boom", type : "DemoError", detail : "More info" },
					type   = "server",
					status = 500
				);
				expect( payload ).notToHaveKey( "detail" );
			} );

			it( "always injects client script for override support", function() {
				expect( service.shouldInjectClientScript() ).toBeTrue();
			} );

			it( "announceUpdateError returns payload after announce", function() {
				// Use a non-singleton instance so mocks do not stick on WireBox's singleton
				var localService = prepareMock( createObject( "component", "cbwire.models.services.CustomErrorHandlingService" ) );
				var mockIS = new tests.resources.MockAnnounceInterceptorService();
				localService.$property( propertyName="moduleSettings", mock=settings );
				localService.$property( propertyName="interceptorService", mock=mockIS );

				var payload = {
					"error"   : true,
					"type"    : "server",
					"status"  : 500,
					"message" : "Boom"
				};
				var result = localService.announceUpdateError(
					event   = getRequestContext(),
					error   = { message : "Boom", type : "Demo" },
					type    = "server",
					status  = 500,
					payload = payload
				);

				expect( result.payload.message ).toBe( "Boom" );
				expect( result.status ).toBe( 500 );
				expect( mockIS.getAnnounceCount() ).toBe( 1 );
				expect( mockIS.getLastState() ).toBe( "onCBWIREUpdateError" );
			} );

			it( "announceUpdateError applies payload and status mutations from interceptData", function() {
				var localService = prepareMock( createObject( "component", "cbwire.models.services.CustomErrorHandlingService" ) );
				var mockIS = new tests.resources.MockAnnounceInterceptorService( shouldMutate = true );
				localService.$property( propertyName="moduleSettings", mock=settings );
				localService.$property( propertyName="interceptorService", mock=mockIS );

				var payload = {
					"error"   : true,
					"type"    : "server",
					"status"  : 500,
					"message" : "Original"
				};
				var result = localService.announceUpdateError(
					event   = getRequestContext(),
					error   = { message : "Original", type : "Demo" },
					type    = "server",
					status  = 500,
					payload = payload
				);

				expect( result.payload.message ).toBe( "Mutated by interceptor" );
				expect( result.status ).toBe( 422 );
				expect( result.payload.status ).toBe( 422 );
			} );

			it( "announceUpdateError still returns original payload if interceptor throws", function() {
				var localService = prepareMock( createObject( "component", "cbwire.models.services.CustomErrorHandlingService" ) );
				var mockIS = new tests.resources.MockAnnounceInterceptorService( shouldThrow = true );
				localService.$property( propertyName="moduleSettings", mock=settings );
				localService.$property( propertyName="interceptorService", mock=mockIS );

				var payload = {
					"error"   : true,
					"type"    : "server",
					"status"  : 500,
					"message" : "Keep me"
				};
				var result = localService.announceUpdateError(
					event   = getRequestContext(),
					error   = { message : "Keep me", type : "Demo" },
					type    = "server",
					status  = 500,
					payload = payload
				);

				expect( result.payload.message ).toBe( "Keep me" );
				expect( result.status ).toBe( 500 );
			} );

		} );
	}

}
