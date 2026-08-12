// Registers happy-dom's window/document globals before each test file
// loads, so the viewer modules (which touch the DOM at call time) can be
// imported and exercised without a browser.
import { GlobalRegistrator } from '@happy-dom/global-registrator';

GlobalRegistrator.register();
