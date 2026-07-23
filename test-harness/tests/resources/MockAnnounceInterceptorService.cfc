/**
 * Test double for interceptorService.announce used by CustomErrorHandlingServiceSpec.
 */
component {

	property name="shouldThrow" type="boolean" default="false";
	property name="shouldMutate" type="boolean" default="false";
	property name="announceCount" type="numeric" default="0";
	property name="lastState" default="";

	function init( boolean shouldThrow = false, boolean shouldMutate = false ) {
		variables.shouldThrow  = arguments.shouldThrow;
		variables.shouldMutate = arguments.shouldMutate;
		variables.announceCount = 0;
		variables.lastState = "";
		return this;
	}

	function announce( required string state, struct data = {} ) {
		variables.announceCount++;
		variables.lastState = arguments.state;

		if ( variables.shouldThrow ) {
			throw( type="InterceptorException", message="Interceptor blew up" );
		}

		if ( variables.shouldMutate && structKeyExists( arguments.data, "payload" ) ) {
			arguments.data.payload.message = "Mutated by interceptor";
			arguments.data.status = 422;
		}

		return true;
	}

	function getAnnounceCount() {
		return variables.announceCount;
	}

	function getLastState() {
		return variables.lastState;
	}

}
