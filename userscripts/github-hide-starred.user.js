// ==UserScript==
// @name         GitHub: скрыть репозитории, которые уже у меня в звёздах
// @namespace    local.hide-starred
// @version      1.3
// @match        https://github.com/*
// @grant        none
// @run-at       document-idle
// @noframes
// @downloadURL  https://raw.githubusercontent.com/PhysShell/dotfiles/main/userscripts/github-hide-starred.user.js
// @updateURL    https://raw.githubusercontent.com/PhysShell/dotfiles/main/userscripts/github-hide-starred.user.js
// ==/UserScript==
(function () {
  'use strict';
  const TAG = '[hide-starred]';
  const LIST_ROW = '.col-12.d-block, #user-repositories-list li';
  const ROW = LIST_ROW + ', li.pinned-item-list-item';
  const MAX_AUTO_PAGES = 30;
  let showAll = false;
  let lastCount = -1;
  let lastAutoHref = null;

  function scan() {
    let count = 0;
    document.querySelectorAll('.starring-container').forEach(c => {
      const row = c.closest(ROW);
      if (!row) return;
      const mine = c.classList.contains('on');
      if (mine) count++;
      if (mine && !showAll) row.style.setProperty('display', 'none', 'important');
      else row.style.removeProperty('display');
      const opacity = mine && showAll ? '0.35' : '';
      if (row.style.opacity !== opacity) row.style.opacity = opacity;
    });
    if (count !== lastCount) { console.log(TAG, 'уже в моих звёздах на странице:', count); lastCount = count; }
    updateButton(count);
    maybeGoNext();
  }

  function listRows() {
    return [...document.querySelectorAll(LIST_ROW)].filter(r => r.querySelector('.starring-container'));
  }

  function findNext() {
    const links = document.querySelectorAll('.paginate-container a, .pagination a, a[rel="next"]');
    return [...links].find(a => a.rel === 'next' || a.classList.contains('next_page') || a.textContent.trim() === 'Next');
  }

  function getSkips() { try { return +sessionStorage.getItem('hs-skips') || 0; } catch { return 0; } }
  function setSkips(n) { try { sessionStorage.setItem('hs-skips', String(n)); } catch {} }

  function maybeGoNext() {
    if (showAll) return;
    const rows = listRows();
    if (!rows.length) return;
    const visible = rows.filter(r => r.style.display !== 'none');
    if (visible.length) { setSkips(0); return; }

    const next = findNext();
    if (!next) { console.log(TAG, 'всё скрыто, но кнопки Next нет (последняя страница)'); return; }
    if (next.href === lastAutoHref) return;
    const skips = getSkips();
    if (skips >= MAX_AUTO_PAGES) { console.log(TAG, `пропущено ${skips} страниц подряд, останавливаюсь`); return; }

    lastAutoHref = next.href;
    setSkips(skips + 1);
    console.log(TAG, 'все строки скрыты, перехожу на следующую страницу:', next.href);
    setTimeout(() => next.click(), 500);
  }

  function updateButton(count) {
    let btn = document.getElementById('hs-toggle');
    if (!count) { if (btn) btn.remove(); return; }
    if (!btn) {
      btn = document.createElement('button');
      btn.id = 'hs-toggle';
      btn.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:9999;padding:6px 10px;' +
        'border-radius:6px;font-size:12px;cursor:pointer;border:1px solid #d0d7de;background:#fff;color:#1f2328';
      btn.addEventListener('click', () => { showAll = !showAll; scan(); });
      document.body.appendChild(btn);
    }
    const text = showAll ? `Скрыть уже отмеченные (${count})` : `Скрыто уже отмеченных: ${count} — показать`;
    if (btn.textContent !== text) btn.textContent = text;
  }

  let timer;
  const schedule = (delay = 200) => { clearTimeout(timer); timer = setTimeout(scan, delay); };
  new MutationObserver(() => schedule()).observe(document.documentElement, { childList: true, subtree: true });
  document.addEventListener('turbo:load', () => schedule());
  document.addEventListener('turbo:frame-load', () => schedule());
  document.addEventListener('click', () => schedule(800), true);
  scan();
})();
