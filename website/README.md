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
