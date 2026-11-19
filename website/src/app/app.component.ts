import { Component, DestroyRef, inject } from '@angular/core';
import { DOCUMENT } from '@angular/common';
import { ActivatedRoute, NavigationEnd, Router, RouterOutlet } from '@angular/router';
import { Meta } from '@angular/platform-browser';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';

@Component({
  selector: 'mizani-root',
  standalone: true,
  imports: [RouterOutlet],
  template: '<router-outlet />',
})
export class AppComponent {
  private readonly destroyRef = inject(DestroyRef);
  private readonly document = inject(DOCUMENT);
  private readonly meta = inject(Meta);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  constructor() {
    this.router.events
      .pipe(
        filter((event): event is NavigationEnd => event instanceof NavigationEnd),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe(() => this.updatePageMetadata());
  }

  private updatePageMetadata(): void {
    let pageRoute = this.route;
    while (pageRoute.firstChild) pageRoute = pageRoute.firstChild;

    const title = pageRoute.snapshot.title ?? this.document.title;
    const description = pageRoute.snapshot.data['description'] as string | undefined;
    if (description) {
      this.meta.updateTag({ name: 'description', content: description });
      this.meta.updateTag({ property: 'og:description', content: description });
      this.meta.updateTag({ name: 'twitter:description', content: description });
    }
    this.meta.updateTag({ property: 'og:title', content: title });
    this.meta.updateTag({ name: 'twitter:title', content: title });

    const pageUrl = new URL(this.router.url.split(/[?#]/, 1)[0], this.document.baseURI);
    const imageUrl = new URL('/assets/mizani-social-preview.jpg', this.document.baseURI);
    this.meta.updateTag({ property: 'og:url', content: pageUrl.href });
    this.meta.updateTag({ property: 'og:image', content: imageUrl.href });
    this.meta.updateTag({ name: 'twitter:image', content: imageUrl.href });

    const robots = pageRoute.snapshot.data['robots'] as string | undefined;
    if (robots) this.meta.updateTag({ name: 'robots', content: robots });
    else this.meta.removeTag('name="robots"');
  }
}
