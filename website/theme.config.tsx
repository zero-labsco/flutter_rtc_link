import type { DocsThemeConfig } from 'nextra-theme-docs'
import React from 'react'

// Dark instrument-panel look: amber signal color on a near-black surface.
// The same palette as the example app (brandSeed #E8A33D), so docs and demo
// read as one product.
const config: DocsThemeConfig = {
  logo: (
    <span className="rtclink-logo">
      <span className="rtclink-logo-led" /> Flutter RTC Link
    </span>
  ),
  project: {
    link: 'https://github.com/zero-labsco/flutter_rtc_link'
  },
  docsRepositoryBase:
    'https://github.com/zero-labsco/flutter_rtc_link/tree/main/website',
  footer: {
    content: 'Flutter RTC Link · MPL-2.0'
  },
  // The instrument panel is dark by design; light mode would break the mono
  // readout contrast used throughout the code samples and tables.
  darkMode: false,
  // The amber accent is applied with CSS custom properties in
  // styles/instrument.css (nextra 3 dropped `primaryHue`).
  // 琥珀强调色由 styles/instrument.css 中的 CSS 变量提供
  //（nextra 3 已移除 `primaryHue`）。
  search: {
    placeholder: 'Search the docs…'
  },
  editLink: {
    content: 'Edit this page on GitHub'
  },
  feedback: {
    content: 'Questions? Open an issue'
  },
  sidebar: {
    defaultMenuCollapseLevel: 1
  },
  toc: {
    backToTop: 'Back to top'
  },
  head: (
    <>
      <link
        rel="icon"
        href="/flutter_rtc_link/favicon.svg"
        type="image/svg+xml"
      />
      <link rel="preconnect" href="https://fonts.googleapis.com" />
      <link
        rel="preconnect"
        href="https://fonts.gstatic.com"
        crossOrigin="anonymous"
      />
      <link
        href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&family=Noto+Sans+SC:wght@400;500;700&display=swap"
        rel="stylesheet"
      />
    </>
  )
}

export default config
