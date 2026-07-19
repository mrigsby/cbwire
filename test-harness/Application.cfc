/**
********************************************************************************
Copyright 2005-2007 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.ortussolutions.com
********************************************************************************
*/
component{

	// UPDATE THE NAME OF THE MODULE IN TESTING BELOW
	request.MODULE_NAME = "cbwire";

	// Application properties
	this.name              = hash( getCurrentTemplatePath() );
	this.sessionManagement = true;
	this.sessionTimeout    = createTimeSpan(0,0,15,0);
	this.setClientCookies  = true;

	/**************************************
	LUCEE Specific Settings
	**************************************/
	// buffer the output of a tag/function body to output in case of a exception
	this.bufferOutput 					= true;
	// Activate Gzip Compression
	this.compression 					= false;
	// Turn on/off white space managemetn
	this.whiteSpaceManagement 			= "smart";
	// Turn on/off remote cfc content whitespace
	this.suppressRemoteComponentContent = false;

	// COLDBOX STATIC PROPERTY, DO NOT CHANGE UNLESS THIS IS NOT THE ROOT OF YOUR COLDBOX APP
	COLDBOX_APP_ROOT_PATH       = getDirectoryFromPath( getCurrentTemplatePath() );
	// The web server mapping to this application. Used for remote purposes or static purposes
	COLDBOX_APP_MAPPING         = "";
	// COLDBOX PROPERTIES
	COLDBOX_CONFIG_FILE 	    = "";
	// COLDBOX APPLICATION KEY OVERRIDE
	COLDBOX_APP_KEY 		    = "";

	// Normalize path for CommandBox, MiniServer, Docker (separators + trailing slash)
	COLDBOX_APP_ROOT_PATH = normalizeDir( COLDBOX_APP_ROOT_PATH );
	this.mappings[ "/root" ] = COLDBOX_APP_ROOT_PATH;

	// Derive module paths from {moduleRoot}/{moduleName}/test-harness/
	// registerAndActivateModule( name, "moduleroot" ) resolves expandPath("/moduleroot") + "/" + name
	// so /moduleroot must be the PARENT of the module folder (not "/" — expandPath breaks).
	modulePath     = parentDir( COLDBOX_APP_ROOT_PATH ); // .../{moduleName}/
	moduleRootPath = parentDir( modulePath );            // .../ (parent of module)

	// Module Root + Path Mappings
	this.mappings[ "/moduleroot" ] = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = modulePath;

	// application start
	public boolean function onApplicationStart(){
		application.cbBootstrap = new coldbox.system.Bootstrap( COLDBOX_CONFIG_FILE, COLDBOX_APP_ROOT_PATH, COLDBOX_APP_KEY, COLDBOX_APP_MAPPING );
		application.cbBootstrap.loadColdbox();
		return true;
	}

	// request start
	public boolean function onRequestStart(String targetPage){

		// Process ColdBox Request
		application.cbBootstrap.onRequestStart( arguments.targetPage );

		return true;
	}

	public void function onSessionStart(){
		application.cbBootStrap.onSessionStart();
	}

	public void function onSessionEnd( struct sessionScope, struct appScope ){
		arguments.appScope.cbBootStrap.onSessionEnd( argumentCollection=arguments );
	}

	public boolean function onMissingTemplate( template ){
		return application.cbBootstrap.onMissingTemplate( argumentCollection=arguments );
	}

	/**
	 * Forward slashes + trailing slash.
	 */
	private string function normalizeDir( required string path ) {
		var p = replace( arguments.path, "\", "/", "all" );
		// collapse duplicate slashes except leading //
		p = reReplace( p, "([^:])//+", "\1/", "all" );
		if ( !len( p ) ) {
			return "/";
		}
		if ( right( p, 1 ) != "/" ) {
			p &= "/";
		}
		return p;
	}

	/**
	 * Parent directory with trailing slash. "/foo/bar/" → "/foo/"
	 */
	private string function parentDir( required string path ) {
		var p = normalizeDir( arguments.path );
		// strip trailing slash for list ops
		p = reReplace( p, "/$", "" );
		if ( !len( p ) || p == "" ) {
			return "/";
		}
		var depth = listLen( p, "/" );
		if ( depth <= 1 ) {
			// "/cbwire" → parent is "/"
			return "/";
		}
		return "/" & listDeleteAt( p, depth, "/" ) & "/";
	}

}
