/* Équivalents des SF Symbols utilisés par l'app Mac.
   Tracés Material Icons (Apache 2.0) ou dessinés ici. */
(function () {
  const P = {
    eye: '<path fill-rule="evenodd" d="M12 5C6.5 5 2.7 9.2 1.5 12c1.2 2.8 5 7 10.5 7s9.3-4.2 10.5-7C21.3 9.2 17.5 5 12 5Zm0 3.4a3.6 3.6 0 1 1 0 7.2 3.6 3.6 0 0 1 0-7.2Z"/>',
    hand: '<path d="M21.5 6.5V18c0 2.5-2 4.5-4.5 4.5h-5.6c-1.1 0-2.1-.4-2.9-1.2L3 15.8s1.1-1.1 1.2-1.1c.2-.2.5-.3.8-.3.2 0 .4.1.6.2l3.4 1.9V5.2c0-.8.7-1.5 1.5-1.5s1.5.7 1.5 1.5v6h.8V3c0-.8.7-1.5 1.5-1.5S16 2.2 16 3v8.2h.8V4.3c0-.8.7-1.5 1.5-1.5s1.5.7 1.5 1.5v6.9h.4V6.5c0-.8.4-1.3 1-1.3s.3 0 .3 1.3Z"/>',
    stopCircle: '<path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm4 14H8V8h8v8z"/>',
    stop: '<rect x="5" y="5" width="14" height="14" rx="2.5"/>',
    lock: '<path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z"/>',
    book: '<path d="M18 2H6c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zM6 4h5v8l-2.5-1.5L6 12V4z"/>',
    check: '<path d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>',
    checkCircle: '<path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>',
    circle: '<circle cx="12" cy="12" r="9.5" fill="none" stroke="currentColor" stroke-width="1.8"/>',
    circleDotted: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="0.1 4.6"/>',
    mic: '<path d="M12 14c1.66 0 2.99-1.34 2.99-3L15 5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.3-3c0 3-2.54 5.1-5.3 5.1S6.7 14 6.7 11H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c3.28-.48 6-3.3 6-6.72h-1.7z"/>',
    play: '<path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.2-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z"/>',
    xmark: '<path d="M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>',
    photo: '<path fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round" d="M4.5 4.5h15a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-13a1 1 0 0 1 1-1Z"/><path d="m5.5 17.5 4-5 3 3.5 2.5-3 3.5 4.5z"/><circle cx="15.5" cy="8.5" r="1.6"/>',
    doc: '<path fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round" d="M6.5 2.8h7.2l4.8 4.8v13.6H6.5Z M13.5 3v4.8h4.8"/><path d="M9 12h6v1.6H9zm0 3.4h6V17H9z"/>',
    download: '<circle cx="12" cy="12" r="9.2" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M11.1 7h1.8v6.2l2.4-2.4 1.3 1.3-4.6 4.6-4.6-4.6 1.3-1.3 2.4 2.4z"/>',
    desktop: '<path d="M21 2H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h7v2H8v2h8v-2h-2v-2h7c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H3V4h18v12z"/>',
    film: '<path d="M18 4l2 4h-3l-2-4h-2l2 4h-3l-2-4H8l2 4H7L5 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V4h-4z"/>',
    music: '<path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/>',
    list: '<path d="M2 17h2v.5H3v1h1v.5H2v1h3v-4H2v1zm1-9h1V4H2v1h1v3zm-1 3h1.8L2 13.1v.9h3v-1H3.2L5 10.9V10H2v1zm5-6v2h14V5H7zm0 14h14v-2H7v2zm0-6h14v-2H7v2z"/>',
    personWave: '<path d="M9 13c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4zm7.76-9.64-1.68 1.69c.84 1.18.84 2.71 0 3.89l1.68 1.69c2.02-2.02 2.02-5.07 0-7.27zM20.07 2l-1.63 1.63c2.77 3.02 2.77 7.56 0 10.74L20.07 16c3.9-3.89 3.91-9.95 0-14z"/>',
    exclam: '<path d="M11 15h2v2h-2zm0-8h2v6h-2zm.99-5C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8z"/>',
    gear: '',
    /* glyphes blancs des applications */
    mail: '<path d="M20 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4-8 5-8-5V6l8 5 8-5v2z"/>',
    globe: '<path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/>',
    video: '<path d="M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11l-4 4z"/>',
    folder: '<path d="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"/>',
    calendar: '<path d="M19 4h-1V2h-2v2H8V2H6v2H5c-1.11 0-1.99.9-1.99 2L3 20a2 2 0 0 0 2 2h14c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 16H5V10h14v10z"/>',
    photos: '<path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/>',
    app: '<rect x="4" y="4" width="16" height="16" rx="4" fill="none" stroke="currentColor" stroke-width="1.9"/>',
  };
  // Roue dentée façon « gearshape » : 8 dents, trou central.
  (function () {
    const n = 8, R = 10, r = 7.6, pts = [];
    for (let i = 0; i < n * 4; i++) {
      const a = (i / (n * 4)) * Math.PI * 2 - Math.PI / (n * 4) * 1.5;
      const rad = (i % 4 === 0 || i % 4 === 1) ? R : r;
      pts.push((12 + rad * Math.cos(a)).toFixed(2) + ' ' + (12 + rad * Math.sin(a)).toFixed(2));
    }
    P.gear = '<path fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round" d="M' +
      pts.join(' L') + 'Z"/><circle cx="12" cy="12" r="3.2" fill="none" stroke="currentColor" stroke-width="1.7"/>';
  })();
  window.icon = function (name, size, color) {
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="' + (color || 'currentColor') +
      '" aria-hidden="true">' + (P[name] || P.app) + '</svg>';
  };
})();
