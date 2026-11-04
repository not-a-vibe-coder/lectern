// Lectern landing: scroll reveals, the highlighter sweep and the nav border.
(function () {
  var reveal = document.querySelectorAll('[data-reveal]');
  // Stagger siblings that reveal together (cards, steps, features): 60 ms apart.
  reveal.forEach(function (el) {
    var group = Array.prototype.filter.call(el.parentElement.children, function (c) {
      return c.hasAttribute('data-reveal');
    });
    if (group.length > 1) el.style.setProperty('--i', Math.min(group.indexOf(el), 5));
  });
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { threshold: 0.08, rootMargin: '0px 0px -8% 0px' });
    reveal.forEach(function (el) { io.observe(el); });
  } else {
    reveal.forEach(function (el) { el.classList.add('in'); });
  }

  var nav = document.querySelector('[data-nav]');
  var ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      nav.classList.toggle('is-scrolled', window.scrollY > 8);
      ticking = false;
    });
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
})();
