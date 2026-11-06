// 设置截图：点标签、按箭头、左右滑都是同一件事——换一页。
// 轨道只占最高那一页的高度，换页时不再改：四页长短差一倍，跟着当前页走的话
// 下面的标签和箭头会上下跑。
(function () {
  var boxes = document.querySelectorAll('[data-shots]');

  Array.prototype.forEach.call(boxes, function (box) {
    var track = box.querySelector('.shots-track');
    var slides = box.querySelectorAll('.shot-slide');
    var tabs = box.querySelectorAll('.shots-tab');
    var current = 0;

    if (!track || !slides.length) return;

    function show(index) {
      current = (index + slides.length) % slides.length;
      Array.prototype.forEach.call(slides, function (slide, i) {
        slide.classList.toggle('on', i === current);
      });
      Array.prototype.forEach.call(tabs, function (tab, i) {
        tab.setAttribute('aria-pressed', i === current ? 'true' : 'false');
      });
    }

    // 最高的那一页有多高，轨道就多高；短的页在中间，上面下面留白。
    function fit() {
      var tallest = 0;
      Array.prototype.forEach.call(slides, function (slide) {
        tallest = Math.max(tallest, slide.getBoundingClientRect().height);
      });
      if (tallest) track.style.height = tallest + 'px';
    }

    Array.prototype.forEach.call(tabs, function (tab, i) {
      tab.addEventListener('click', function () { show(i); });
    });

    Array.prototype.forEach.call(box.querySelectorAll('.shots-arrow'), function (arrow) {
      arrow.addEventListener('click', function () {
        show(current + Number(arrow.dataset.step));
      });
    });

    // 手机上左右滑，和箭头同一条路
    var startX = null;
    track.addEventListener('touchstart', function (e) {
      startX = e.touches[0].clientX;
    }, { passive: true });
    track.addEventListener('touchend', function (e) {
      if (startX === null) return;
      var dx = e.changedTouches[0].clientX - startX;
      startX = null;
      if (Math.abs(dx) > 40) show(current + (dx < 0 ? 1 : -1));
    });

    // 图片解码完、字体加载完、窗口变宽变窄，都会改变页面的高度
    var settle = function () { show(current); fit(); };
    window.addEventListener('resize', settle);
    window.addEventListener('load', settle);
    Array.prototype.forEach.call(track.querySelectorAll('img'), function (img) {
      if (!img.complete) img.addEventListener('load', settle);
    });

    // 键盘：焦点在轮播里时，方向键翻页
    box.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowLeft') { show(current - 1); e.preventDefault(); }
      if (e.key === 'ArrowRight') { show(current + 1); e.preventDefault(); }
    });

    show(0);
    fit();
  });
})();
