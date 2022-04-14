import {
  JupyterFrontEnd,
  JupyterFrontEndPlugin
} from '@jupyterlab/application';

import { IThemeManager } from '@jupyterlab/apputils';

/**
 * Initialization data for the charmerstheme extension.
 */
const extension: JupyterFrontEndPlugin<void> = {
  id: 'charmerstheme',
  requires: [IThemeManager],
  autoStart: true,
  activate: (app: JupyterFrontEnd, manager: IThemeManager) => {
    console.log('JupyterLab extension charmerstheme is activated!');
    const style = 'charmerstheme/index.css';

    manager.register({
      name: 'charmerstheme',
      isLight: true,
      load: () => manager.loadCSS(style),
      unload: () => Promise.resolve(undefined)
    });
  }
};

export default extension;
