// AWA 가이드 — 사이드바 스크롤스파이 + 모바일 메뉴

const menuBtn = document.getElementById('menuBtn');
const sidebar = document.getElementById('sidebar');

// 모바일 백드롭 (열림 시 본문 위 오버레이, 클릭하면 닫힘)
const backdrop = document.createElement('div');
backdrop.className = 'sidebar-backdrop';
document.body.appendChild(backdrop);

function openSidebar(open) {
  sidebar.classList.toggle('open', open);
  backdrop.classList.toggle('show', open);
  if (menuBtn) menuBtn.setAttribute('aria-expanded', String(open));
  // 닫힘 시 화면 밖 링크로 키보드 포커스가 가지 않도록
  if (window.innerWidth <= 900) sidebar.toggleAttribute('inert', !open);
  document.body.style.overflow = open ? 'hidden' : '';
}

if (menuBtn) {
  menuBtn.addEventListener('click', () => openSidebar(!sidebar.classList.contains('open')));
}
backdrop.addEventListener('click', () => openSidebar(false));
document.addEventListener('keydown', e => {
  if (e.key === 'Escape' && sidebar.classList.contains('open')) openSidebar(false);
});

// 사이드바 링크 클릭 시 모바일에서 닫기
sidebar.querySelectorAll('a').forEach(a => {
  a.addEventListener('click', () => {
    if (window.innerWidth <= 900) openSidebar(false);
  });
});

// 데스크톱으로 넓어지면 모바일 열림 상태 초기화
let rt;
window.addEventListener('resize', () => {
  clearTimeout(rt);
  rt = setTimeout(() => {
    if (window.innerWidth > 900) {
      openSidebar(false);
      sidebar.removeAttribute('inert');
    }
  }, 120);
});
// 초기: 모바일이면 닫힘(inert), 데스크톱이면 정상
if (window.innerWidth <= 900) sidebar.setAttribute('inert', '');

// 터미널 "복사" 버튼 — 해당 터미널의 명령($ 또는 > 로 시작하는 줄)을 클립보드로
document.querySelectorAll('.tb-copy').forEach(btn => {
  btn.addEventListener('click', async () => {
    const term = btn.closest('.terminal');
    if (!term) return;
    const body = term.querySelector('.terminal-body');
    // 프롬프트 기호(t-prompt)가 있는 줄에서 명령부만 추출
    const cmds = [];
    body.querySelectorAll('.line, .tg-row').forEach(line => {
      const prompt = line.querySelector('.t-prompt');
      if (!prompt) return;
      // 주석(.t-cmt) 제외하고 텍스트만
      const clone = line.cloneNode(true);
      clone.querySelectorAll('.t-cmt, .t-prompt').forEach(n => n.remove());
      const text = clone.textContent.replace(/\s+/g, ' ').trim();
      if (text) cmds.push(text);
    });
    const payload = cmds.join('\n');
    if (!payload) return;
    try {
      await navigator.clipboard.writeText(payload);
      const orig = btn.innerHTML;
      btn.classList.add('copied');
      btn.innerHTML = '<span aria-hidden="true">✓</span> 복사됨';
      setTimeout(() => { btn.classList.remove('copied'); btn.innerHTML = orig; }, 1600);
    } catch (e) { /* clipboard 미지원 환경은 무시 */ }
  });
});

// ─────────────────────── 탭 시스템 (테마별 전환) ───────────────────────
const TABS = ['start', 'how', 'ops', 'ref'];
const tabBtns = Array.from(document.querySelectorAll('.topbar .tab'));
const tabPanels = new Map();   // tab -> panel div
const sideGroups = new Map();  // tab -> 사이드바 그룹
document.querySelectorAll('main .tab-panel').forEach(p => tabPanels.set(p.dataset.tab, p));
sidebar.querySelectorAll('.side-group').forEach(g => sideGroups.set(g.dataset.tab, g));

let currentTab = 'start';

// 섹션 id → 어느 탭에 속하는지
const sectionTab = new Map();
tabPanels.forEach((panel, tab) => {
  panel.querySelectorAll('.section').forEach(s => sectionTab.set(s.id, tab));
});

function switchTab(tab, opts = {}) {
  if (!TABS.includes(tab)) return;
  currentTab = tab;
  tabBtns.forEach(b => b.setAttribute('aria-selected', String(b.dataset.tab === tab)));
  tabPanels.forEach((p, t) => p.toggleAttribute('hidden', t !== tab));
  sideGroups.forEach((g, t) => g.toggleAttribute('hidden', t !== tab));
  if (!opts.keepScroll) window.scrollTo({ top: 0, behavior: opts.smooth ? 'smooth' : 'auto' });
  // 탭 전환 시 그 탭 첫 섹션을 active 로
  const first = tabPanels.get(tab)?.querySelector('.section');
  if (first) activate(first.id);
  if (typeof refreshRevealsFor === 'function') refreshRevealsFor(tab);
  onScroll();
}

tabBtns.forEach(btn => {
  btn.addEventListener('click', () => switchTab(btn.dataset.tab, { smooth: false }));
});

// 스크롤스파이 — 활성 탭 안의 섹션만 대상으로
const allSections = Array.from(document.querySelectorAll('main .section'));
function liveSections() { return allSections.filter(s => sectionTab.get(s.id) === currentTab); }

const navLinks = new Map();
sidebar.querySelectorAll('a[href^="#"]').forEach(a => {
  navLinks.set(a.getAttribute('href').slice(1), a);
});

function activate(id) {
  if (!id) return;
  navLinks.forEach((a, key) => a.classList.toggle('active', key === id));
}

// 탭 간 점프 링크 (data-goto="ops" href="#dashboard") — 탭 전환 후 해당 섹션으로
document.querySelectorAll('a[data-goto]').forEach(a => {
  a.addEventListener('click', e => {
    e.preventDefault();
    const tab = a.dataset.goto;
    const target = a.getAttribute('href')?.slice(1);
    switchTab(tab, { keepScroll: true });
    requestAnimationFrame(() => {
      const el = document.getElementById(target);
      if (el) { el.scrollIntoView({ behavior: 'smooth' }); activate(target); clickLockUntil = performance.now() + 700; }
    });
  });
});

// 스크롤스파이 — 앵커 점프 시 섹션은 scroll-padding-top(84px) 위치에 멈춘다.
// 그 멈춤선 + 여유(=LINE)를 기준선으로, "기준선을 지나 올라온 섹션 중 가장 아래"를 active.
// (이전엔 기준선이 56px 라 점프 후 섹션 top 84 가 기준선에 못 닿아 한 칸 위가 잡혔다)
const LINE = 96; // scroll-padding-top(84) + 여유 12
let clickLockUntil = 0; // 클릭 직후 잠깐 갱신을 잠가 smooth scroll 중 이전 섹션이 덮어쓰지 않게

function pickActive() {
  if (performance.now() < clickLockUntil) return;
  const secs = liveSections();
  let best = null, bestTop = -Infinity;
  for (const sec of secs) {
    const top = sec.getBoundingClientRect().top - LINE;
    // 기준선 위로(top<=0) 올라온 섹션 중 기준선에 가장 가까운(=top 이 가장 큰) 것
    if (top <= 0 && top > bestTop) { bestTop = top; best = sec.id; }
  }
  // 아직 첫 섹션도 기준선에 안 닿았으면 첫 섹션
  if (!best) best = secs[0]?.id;
  // 페이지 최하단이면 마지막 섹션 강제
  if (window.innerHeight + window.scrollY >= document.body.scrollHeight - 2) {
    best = secs[secs.length - 1]?.id;
  }
  activate(best);
}

let ticking = false;
function onScroll() {
  if (ticking) return;
  ticking = true;
  requestAnimationFrame(() => { pickActive(); ticking = false; });
}
window.addEventListener('scroll', onScroll, { passive: true });
window.addEventListener('resize', onScroll, { passive: true });

// 클릭 시: 즉시 해당 항목 active + 잠금(smooth scroll 동안 이전 섹션이 덮어쓰지 않게)
navLinks.forEach((a, id) => {
  a.addEventListener('click', () => {
    activate(id);
    clickLockUntil = performance.now() + 700; // smooth scroll 평균 소요시간
  });
});

onScroll();

// ─────────────────────── 진입 애니메이션 (절제) ───────────────────────
// reveal 대상에 .reveal 부여 → 화면에 들어오면 .is-in. 1회성.
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const revealEls = Array.from(document.querySelectorAll(
  'main .section > .card-grid, main .section > .callout, main .section > .terminal,' +
  'main .section > .pipeline, main .section > .steps, main .section > .axes,' +
  'main .section > .grades, main .section > .classify, main .section > .card'
));
revealEls.forEach(el => el.classList.add('reveal'));

// 감시 4축 카드에 stagger 인덱스 주입
document.querySelectorAll('.axes .axis-row').forEach((row, i) => {
  row.style.setProperty('--i', String(i));
});

// 합의 게이트 — 만장일치 차단 라인 1회 플래시 대상 지정
const gateLine = document.querySelector('#gate .terminal-body .line:last-child');
if (gateLine) gateLine.classList.add('gate-flash');

function showAll() {
  revealEls.forEach(el => el.classList.add('is-in'));
  if (gateLine) gateLine.classList.add('is-in');
}

let io = null;
// reduced-motion 이거나 observer 미지원이면 즉시 전부 표시(모션만 끄고 콘텐츠는 보존)
if (reduceMotion || !('IntersectionObserver' in window)) {
  showAll();
} else {
  io = new IntersectionObserver((entries, obs) => {
    entries.forEach(e => {
      if (e.isIntersecting) { e.target.classList.add('is-in'); obs.unobserve(e.target); }
    });
  }, { rootMargin: '0px 0px -12% 0px', threshold: 0.08 });
  revealEls.forEach(el => io.observe(el));
  if (gateLine) io.observe(gateLine);
}

// 탭 전환 시: 새로 보이는 패널의 reveal 요소를 다시 관찰(숨겨졌던 동안 콜백을 못 받았을 수 있음).
// 이미 화면 안에 들어온 것은 즉시 is-in 처리.
function refreshRevealsFor(tab) {
  if (!io) return;
  const panel = tabPanels.get(tab);
  if (!panel) return;
  panel.querySelectorAll('.reveal:not(.is-in), .gate-flash:not(.is-in)').forEach(el => {
    const r = el.getBoundingClientRect();
    if (r.top < window.innerHeight && r.bottom > 0) el.classList.add('is-in');
    else io.observe(el);
  });
}
// 초기 진입: URL 해시가 특정 섹션이면 그 탭으로
const initHash = location.hash.slice(1);
if (initHash && sectionTab.has(initHash)) {
  switchTab(sectionTab.get(initHash), { keepScroll: true });
  requestAnimationFrame(() => {
    document.getElementById(initHash)?.scrollIntoView();
    activate(initHash);
    clickLockUntil = performance.now() + 500; // 스크롤 안착 전 onScroll 이 첫 섹션으로 덮지 않게
  });
} else {
  switchTab('start', { keepScroll: true });
}
refreshRevealsFor(currentTab);
