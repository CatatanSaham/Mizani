import { Component, signal } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';

export const MIZANI_PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.mizani.money';

@Component({
  selector: 'mizani-site-header',
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  template: `
    <a class="skip-link" href="#main-content">Skip to content</a>
    <header class="site-header" (keydown.escape)="onEscape($event, menuButton)">
      <div class="header-inner">
        <a class="brand-lockup" routerLink="/" (click)="closeMenu()" aria-label="Mizani home">
          <img src="/assets/mizani-logo.png" alt="" width="36" height="36">
          <span>Mizani</span>
        </a>
        <button #menuButton class="menu-toggle" type="button" [attr.aria-expanded]="menuOpen()" aria-controls="main-nav" (click)="toggleMenu()">
          {{ menuOpen() ? 'Close menu' : 'Menu' }}
        </button>
        <nav id="main-nav" [class.mobile-menu-open]="menuOpen()" aria-label="Main navigation">
          <a routerLink="/" fragment="the-app" (click)="closeMenu()">The app</a>
          <a routerLink="/" fragment="offline-first" (click)="closeMenu()">Offline first</a>
          <a class="nav-report" routerLink="/analysis" routerLinkActive="nav-active" ariaCurrentWhenActive="page" (click)="closeMenu()">Report workspace</a>
        </nav>
      </div>
    </header>
  `,
})
export class SiteHeaderComponent {
  readonly menuOpen = signal(false);

  toggleMenu(): void {
    this.menuOpen.update((open) => !open);
  }

  closeMenu(): void {
    this.menuOpen.set(false);
  }

  onEscape(event: Event, button: HTMLButtonElement): void {
    if (!this.menuOpen()) return;
    event.preventDefault();
    this.closeMenu();
    button.focus();
  }
}

@Component({
  selector: 'mizani-site-footer',
  standalone: true,
  imports: [RouterLink],
  template: `
    <footer class="site-footer">
      <div class="footer-inner">
        <a class="brand-lockup footer-brand" routerLink="/" aria-label="Mizani home">
          <img src="/assets/mizani-logo.png" alt="" width="36" height="36">
          <span>Mizani</span>
        </a>
        <nav aria-label="Legal and project links">
          <a [href]="playStoreUrl">Get Mizani on Google Play</a>
          <a routerLink="/" fragment="faq">FAQs</a>
          <a routerLink="/terms">Website terms</a>
          <a routerLink="/privacy">Website privacy</a>
          <a href="https://github.com/NyotaFoundry/Mizani">Source on GitHub</a>
        </nav>
        <div class="footer-note">
          <span>© 2026 Mizani</span>
          <span>A product of <a href="https://github.com/NyotaFoundry">Nyota Foundry</a></span>
        </div>
      </div>
    </footer>
  `,
})
export class SiteFooterComponent {
  readonly playStoreUrl = MIZANI_PLAY_STORE_URL;
}
