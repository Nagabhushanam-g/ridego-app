# RideGo website preview

Static, responsive marketing website for RideGo. This is a **development preview**, not a live booking site.

## Preview locally

Extract the complete preview ZIP. Open `website/preview.html`, then select **Open RideGo homepage**. Alternatively, open `website/index.html` directly in Chrome. For a mobile-width preview, press F12 and then Ctrl+Shift+M in Chrome. Keep all website files together in the extracted folder.

To serve locally instead, run `python3 -m http.server 8080` from the website directory and visit `http://localhost:8080`.

## Release checklist

- [ ] Approve official branding, contact details and domain.
- [ ] Add reviewed privacy policy, terms, safety and support pages.
- [ ] Replace coming-soon placeholders with verified public store links only after app release.
- [ ] Test accessibility, mobile layout and browser compatibility.
- [ ] Configure hosting, HTTPS, custom domain, analytics consent and monitoring.
- [ ] Approve public publication; this commit does **not** deploy the website.

The website deliberately has no Firebase keys, sign-in, payment form, or sensitive data collection.

## Current development status

- Responsive homepage and mobile navigation implemented.
- Separate Rider and Partner app sections with SVG icons.
- Partner description includes planned consent-based DigiLocker RC and Driving Licence verification; clearly states that it is not yet available.
- Verification navigation anchor added; draft Privacy and Safety pages describe proposed checks without claiming live verification.
- Mobile tap targets, readable text contrast, and reduced-motion preferences improved.
- Privacy, terms, safety and support pages remain prelaunch placeholders.

## DigiLocker website claims

- [x] Describe government-document verification as a planned feature, not a live service.
- [ ] Obtain authorized DigiLocker Requester access and complete backend integration.
- [ ] Confirm official branding, trademark and integration-description requirements before publication.
- [ ] Confirm consent, privacy, document-retention and review procedures.
- [ ] Replace coming-soon text only after a real end-to-end government-document verification test.

## Next review before publication

1. Visually test at 360px, 390px, 768px and desktop widths.
2. Confirm actual supported service areas and product claims.
3. Supply official support contacts and legal entity information.
4. Approve reviewed legal/safety policies before replacing placeholders.
5. Publish only after explicit launch approval.

## Safety and support content review

- [x] Add general Rider and Partner safety guidance without promising unavailable features.
- [x] Add prelaunch support FAQ and clarify that the website has no monitored support channel.
- [ ] Confirm local emergency guidance and the official incident-response process.
- [ ] Add verified support email/phone and response expectations after staffing is ready.
- [ ] Obtain review and approval of all safety, privacy and terms text before publication.

## Privacy and terms review checklist

- [x] Add preliminary privacy topics: account data, ride/location data, device tokens and Partner document details.
- [x] Add preliminary terms topics: Rider/Partner responsibilities, cash accounting and unavailable payout workflows.
- [ ] Confirm legal entity, registered address, contact details and applicable jurisdiction.
- [ ] Audit actual production data collection, third-party processors, permissions, retention and deletion mechanisms.
- [ ] Define cancellation/refund policy, grievance handling, account appeals and dispute process.
- [ ] Confirm statutory and platform requirements with qualified legal review.
- [ ] Approve final effective-dated documents before making the website public.

## Offline site checks

Run `python3 website/check_site.py` from the repository root to check local page links, anchors, asset references, image alt attributes, and basic page structure. This is a static smoke test, not a replacement for visual browser/device testing or legal review.
