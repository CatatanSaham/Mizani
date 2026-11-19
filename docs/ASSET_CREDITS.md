# Third-party illustration credits

Mizani uses Storyset SVG illustrations from Freepik Company. To keep the main About screen focused, attribution is grouped with other required notices under **Settings > About & privacy > Third-party notices**. The app credits **Illustrations by Storyset (storyset.com), Freepik Company** there.

Storyset's [FAQ](https://storyset.com/faqs) requires attribution when free illustrations are used. Its [Terms of Use](https://storyset.com/terms) allow downloading and modifying Storyset content subject to restrictions, including restrictions on transferring, sublicensing, or reselling the artwork. Keep the Storyset credit in the app's user-accessible Third-party notices, do not distribute the illustrations as standalone assets, and confirm that embedding them in the intended app distribution is covered by the license applicable to the original downloads. Retain the download and license evidence.

| Local asset | Storyset source | App use | Adjustments |
| --- | --- | --- | --- |
| `app/src/main/assets/storyset/finance_cuate.svg` | [Finance, Cuate](https://storyset.com/illustration/finance/cuate) | Onboarding, home empty-ledger hero | Recolored gold accent `#FFC727` to Mizani gold `#E8BF6A`; adapted the character skin tone to `#9B5E49`. |
| `app/src/main/assets/storyset/financial_data_cuate.svg` | [Financial data, Cuate](https://storyset.com/illustration/financial-data/cuate) | Onboarding, Insights and Recurring empty states | Recolored gold accent `#FFC727` to Mizani gold `#E8BF6A`. |
| `app/src/main/assets/storyset/saving_money_cuate.svg` | [Saving money, Cuate](https://storyset.com/illustration/saving-money/cuate) | Final onboarding step | No changes. |

The original SVG structure is retained locally and rendered from app assets. The app does not fetch illustrations at runtime.

## Website promotional assets

The website serves WebP crops of the supplied Mizani Home, Add expense, Wallets and Insights demo
screens. Their originals live under `website/public/assets/app-screens/` and use fictional records.
The hero uses a responsive crop of [Ninthgrid's Lagos smartphone portrait on Pexels](https://www.pexels.com/photo/portrait-of-a-happy-woman-in-lagos-using-smartphone-30689110/).
The offline section uses a separate crop of [Arina Krasnikova's journal-and-phone photograph](https://www.pexels.com/photo/a-woman-taking-notes-while-reading-on-her-smartphone-7005415/).
Both photos are listed as free to use on Pexels and are credited here as a courtesy. The site serves
optimized WebP crops from `website/public/assets/product/`, with local JPEG fallbacks. The 1200 × 630
social preview uses the hero photograph, Mizani logo and official Play badge. Images, fonts and
scripts load locally; the page makes no third-party image requests at runtime. See the
[Pexels license](https://www.pexels.com/license/) for the current usage terms.

The landing-page download link uses Google's official English (U.S.) **Get it on Google Play**
badge from the [Google Play Partner Marketing Hub](https://partnermarketinghub.withgoogle.com/brands/google-play/google-play/lockups-icons-badges/).
The badge is included as supplied, scaled proportionally, and links directly to Mizani's Play
listing. The 1200 × 630 social preview combines the Mizani logo, the official badge, a crop of the
existing lifestyle photograph, and the supplied Android app screenshot. It adds no stock or
generated images and makes no third-party image requests at runtime.
