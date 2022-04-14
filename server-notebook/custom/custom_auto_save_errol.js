// leave at least 2 line with only a star on it below, or doc generation fails
/**
 *
 *
 * Placeholder for custom user javascript
 * mainly to be overridden in profile/static/custom/custom.js
 * This will always be an empty file in IPython
 *
 * User could add any javascript in the `profile/static/custom/custom.js` file.
 * It will be executed by the ipython notebook at load time.
 *
 * Same thing with `profile/static/custom/custom.css` to inject custom css into the notebook.
 *
 *
 * The object available at load time depend on the version of IPython in use.
 * there is no guaranties of API stability.
 *
 * The example below explain the principle, and might not be valid.
 *
 * Instances are created after the loading of this file and might need to be accessed using events:
 *     define([
 *        'base/js/namespace',
 *        'base/js/events'
 *     ], function(IPython, events) {
 *         events.on("app_initialized.NotebookApp", function () {
 *             IPython.keyboard_manager....
 *         });
 *     });
 *
 * __Example 1:__
 *
 * Create a custom button in toolbar that execute `%qtconsole` in kernel
 * and hence open a qtconsole attached to the same kernel as the current notebook
 *
 *    define([
 *        'base/js/namespace',
 *        'base/js/events'
 *    ], function(IPython, events) {
 *        events.on('app_initialized.NotebookApp', function(){
 *            IPython.toolbar.add_buttons_group([
 *                {
 *                    'label'   : 'run qtconsole',
 *                    'icon'    : 'icon-terminal', // select your icon from http://fortawesome.github.io/Font-Awesome/icons
 *                    'callback': function () {
 *                        IPython.notebook.kernel.execute('%qtconsole')
 *                    }
 *                }
 *                // add more button here if needed.
 *                ]);
 *        });
 *    });
 *
 * __Example 2:__
 *
 * At the completion of the dashboard loading, load an unofficial javascript extension
 * that is installed in profile/static/custom/
 *
 *    define([
 *        'base/js/events'
 *    ], function(events) {
 *        events.on('app_initialized.DashboardApp', function(){
 *            require(['custom/unofficial_extension.js'])
 *        });
 *    });
 *
 * __Example 3:__
 *
 *  Use `jQuery.getScript(url [, success(script, textStatus, jqXHR)] );`
 *  to load custom script into the notebook.
 *
 *    // to load the metadata ui extension example.
 *    $.getScript('/static/notebook/js/celltoolbarpresets/example.js');
 *    // or
 *    // to load the metadata ui extension to control slideshow mode / reveal js for nbconvert
 *    $.getScript('/static/notebook/js/celltoolbarpresets/slideshow.js');
 *
 *
 * @module IPython
 * @namespace IPython
 * @class customjs
 * @static
 */

// // //
// Setting an autosave interval automatically, using two different event triggers for robustness
// // // 


// When all documents are loaded, set autosave interval to 10 seconds
//$(window).on('load', function(){
//	var interval = 10 //seconds
//	console.warn('autosave custom.js')
//	console.warn('autosave set to ', interval)
//	IPython.notebook.set_autosave_interval(interval*1000) //milliseconds
//})

// Same as above, but on IPython 'notebook_loaded' event
//$([IPython.events]).on("notebook_loaded.Notebook", function(){
//	var interval = 10 //seconds
//	console.warn('autosave custom.js')
//	console.warn('Setting autosave interval to', interval)
//	IPython.notebook.set_autosave_interval(interval*1000) // milliseconds
//})

// // //
// Setting a custom autosave using setInterval
// // //


var interval = 10; // seconds between each autosave 
var custom_autosave_interval_id; // instantiate global var for setInterval object (allows killing later)

// Waiting on window load with setTimeout seems to be the most universal way of setting up
// a custom autosave.  I had problems with safari using the IPython.events event as a trigger.
// Otherwise, this is asynchronous, so the saving interval will drag a little longer than the interval defined
// above.  BUT, it also means that it shouldn't interfere too much with any autosaving that is initialised
//
$(window).on('load', () => {

        // Delay setting autosave up for 10 seconds to allow ipython to load properly
        setTimeout(()=>{

             console.warn('setting up autosave!')
	     IPython.notebook.set_autosave_interval(0)
		console.warn('autosave is turned off, using custom_autosave_interval_id instead') 
                  
              async function auto_save_func(){
                      var savePromise = await IPython.notebook.save_notebook().catch(
                              (error) => {console.error('autosave error:', error)}
                      )   
                      // Probably want to comment once tested sufficiently
                      console.log('saving!')
              }   

              custom_autosave_interval_id = setInterval(auto_save_func, interval*1000) // milliseconds
        },  
        10000) // delay for setTimeout (10_000 milliseconds)
}

)

// Similar to above, but relies on the IPython.events event to trigger, which I found to be unreliable at times
// Using the window on load, as above, is probably more robust
//IPython.notebook.set_autosave_interval(10000)
//$([IPython.events]).on("notebook_loaded.Notebook", function(){
//
//     console.log('setting up autosave!')
//
//      var interval = 10 // seconds
//
//      async function auto_save_func(){
//              var savePromise = await IPython.notebook.save_notebook().catch(
//                      (error) => {console.error('autosave error:', error)}
//              )
//            console.log('saving!')
//      }
//
//      custom_autosave_interval_id = setInterval(auto_save_func, interval*1000) // milliseconds
//})

// Custom autosave using setInterval and the IPython notebook saving function
//
//var custom_autosave_interval_id;
//
//$([IPython.events]).on("notebook_loaded.Notebook", function(){
//
//	var interval = 10 // seconds
//
//	async function auto_save_func(){
//		var savePromise = await IPython.notebook.save_notebook().catch(
//			(error) => {console.error('autosave error:', error)}
//		)
//	}
//
//	custom_autosave_interval_id = setInterval(auto_save_func, interval*1000) // milliseconds
//}

// More aggressive autosaving interval setting, on each time notebook is saved
// Applies each time notebook is autosaved also (aggressive)
// But allows the autosave interval to be set and triggered on manual user save
// And thus avoiding the need to have users run %autosave 10 in a cell
//
//$([IPython.events]).on("notebook_saved.Notebook", function(){
//	var interval = 10 //seconds
//	console.warn('on save, interval set in custom.js')
//	IPython.notebook.set_autosave_interval(interval*1000) // milliseconds
//})
