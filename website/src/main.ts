import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';

bootstrapApplication(AppComponent, appConfig).catch(() => {
  const root = document.querySelector('mizani-root');
  if (root) {
    root.textContent = 'Mizani could not open this page. Refresh to try again.';
  }
});
