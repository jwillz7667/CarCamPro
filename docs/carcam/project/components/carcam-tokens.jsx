// CarCam design tokens + shared primitives
// Technical instrument-cluster aesthetic.

const CC = {
  // surfaces — iOS 26 dark system backgrounds
  void: '#000000',              // systemBackground dark
  bg: '#1C1C1E',                // secondarySystemBackground
  panel: '#2C2C2E',             // tertiarySystemBackground
  panelHi: '#3A3A3C',           // systemGray4
  rule: 'rgba(84,84,88,0.65)',  // separator dark
  ruleHi: 'rgba(84,84,88,0.95)',

  // text — iOS label hierarchy (dark). These have tuned contrast.
  ink: '#FFFFFF',                    // label
  ink2: 'rgba(235,235,245,0.78)',    // secondaryLabel (was 0.72 → bumped for AA)
  ink3: 'rgba(235,235,245,0.60)',    // tertiaryLabel
  ink4: 'rgba(235,235,245,0.38)',    // quaternaryLabel (was 0.28 → bumped)

  // iOS system signal colors (dark variants)
  amber: '#FF9F0A',      // systemOrange dark
  amberDim: '#C77600',
  cyan: '#64D2FF',       // systemCyan dark
  cyanDim: '#3DA5CC',
  red: '#FF453A',        // systemRed dark
  green: '#30D158',      // systemGreen dark
  blue: '#0A84FF',       // systemBlue dark

  // type — SF Pro stack (iOS system)
  sans: '-apple-system, "SF Pro Text", "SF Pro", BlinkMacSystemFont, "Helvetica Neue", sans-serif',
  sansDisplay: '-apple-system, "SF Pro Display", "SF Pro", BlinkMacSystemFont, "Helvetica Neue", sans-serif',
  mono: 'ui-monospace, "SF Mono", Menlo, Monaco, monospace',
};

// ─── Small caps label ─────────────────────────────────────────
function CCLabel({ children, color = CC.ink3, size = 10, style = {} }) {
  return (
    <div style={{
      fontFamily: CC.mono, fontSize: size, letterSpacing: '0.18em',
      textTransform: 'uppercase', color, fontWeight: 500,
      ...style,
    }}>{children}</div>
  );
}

// ─── Mono numeric readout ─────────────────────────────────────
function CCNum({ value, unit, size = 48, color = CC.ink, unitColor = CC.ink3, weight = 300, style = {} }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, fontFamily: CC.mono, ...style }}>
      <span style={{
        fontSize: size, color, fontWeight: weight,
        fontVariantNumeric: 'tabular-nums', letterSpacing: '-0.02em', lineHeight: 1,
      }}>{value}</span>
      {unit && (
        <span style={{
          fontSize: Math.max(10, size * 0.22), color: unitColor,
          letterSpacing: '0.16em', textTransform: 'uppercase',
        }}>{unit}</span>
      )}
    </div>
  );
}

// ─── Tick marks (horizontal scale) ───────────────────────────
function CCTicks({ count = 20, major = 5, height = 14, color = CC.ink4, majorColor = CC.ink3 }) {
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 0, height, width: '100%' }}>
      {Array.from({ length: count }).map((_, i) => {
        const isMajor = i % major === 0;
        return (
          <div key={i} style={{
            flex: 1, height: isMajor ? height : height * 0.5,
            borderLeft: `1px solid ${isMajor ? majorColor : color}`,
          }} />
        );
      })}
    </div>
  );
}

// ─── Circular gauge (for speed, G-force, etc.) ───────────────
function CCGauge({ value = 0, max = 100, size = 180, label, unit, sublabel, color = CC.amber, startAngle = 135, sweep = 270 }) {
  const r = size / 2 - 8;
  const cx = size / 2, cy = size / 2;
  const pct = Math.max(0, Math.min(1, value / max));

  // arc path
  const polar = (a) => {
    const rad = (a - 90) * Math.PI / 180;
    return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
  };
  const arcPath = (fromA, toA) => {
    const [x1, y1] = polar(fromA);
    const [x2, y2] = polar(toA);
    const large = Math.abs(toA - fromA) > 180 ? 1 : 0;
    return `M ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2}`;
  };

  // ticks
  const tickCount = 41;
  const ticks = Array.from({ length: tickCount }).map((_, i) => {
    const a = startAngle + (sweep * i) / (tickCount - 1);
    const [x1, y1] = polar(a);
    const rad = (a - 90) * Math.PI / 180;
    const isMajor = i % 5 === 0;
    const inner = r - (isMajor ? 10 : 5);
    const x2 = cx + inner * Math.cos(rad);
    const y2 = cy + inner * Math.sin(rad);
    const filled = i / (tickCount - 1) <= pct;
    return (
      <line key={i} x1={x1} y1={y1} x2={x2} y2={y2}
        stroke={filled ? color : CC.ink4}
        strokeWidth={isMajor ? 1.5 : 1}
        opacity={filled ? 1 : 0.6}
      />
    );
  });

  return (
    <div style={{ position: 'relative', width: size, height: size }}>
      <svg width={size} height={size} style={{ display: 'block' }}>
        {/* base track */}
        <path d={arcPath(startAngle, startAngle + sweep)} fill="none" stroke={CC.rule} strokeWidth={1} />
        {/* filled arc */}
        <path d={arcPath(startAngle, startAngle + sweep * pct)} fill="none" stroke={color} strokeWidth={2} strokeLinecap="butt" />
        {ticks}
      </svg>
      <div style={{
        position: 'absolute', inset: 0,
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', gap: 2,
      }}>
        {label && <CCLabel size={9}>{label}</CCLabel>}
        <CCNum value={value} unit={unit} size={size * 0.28} color={color} weight={200} />
        {sublabel && <CCLabel size={9} color={CC.ink4}>{sublabel}</CCLabel>}
      </div>
    </div>
  );
}

// ─── Live-feed placeholder (diagonal stripes) ────────────────
function CCFeedPlaceholder({ label = 'LIVE FEED', style = {}, children }) {
  return (
    <div style={{
      position: 'relative', overflow: 'hidden',
      background: `repeating-linear-gradient(135deg,
        ${CC.panel} 0px, ${CC.panel} 14px,
        ${CC.panelHi} 14px, ${CC.panelHi} 15px)`,
      ...style,
    }}>
      <div style={{
        position: 'absolute', inset: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <div style={{
          fontFamily: CC.mono, fontSize: 10, letterSpacing: '0.3em',
          color: CC.ink3, padding: '6px 10px',
          border: `1px solid ${CC.ruleHi}`,
          background: 'rgba(5,7,10,0.7)',
        }}>{label}</div>
      </div>
      {children}
    </div>
  );
}

// ─── Crosshair overlay (adds to any container) ───────────────
function CCCrosshair({ color = CC.ink4, size = 10 }) {
  return (
    <>
      {['0 0', 'auto 0', '0 auto', 'auto auto'].map((pos, i) => {
        const [v, h] = pos.split(' ');
        const [top, right, bottom, left] = [
          v === '0' ? 0 : 'auto', h === 'auto' ? 0 : 'auto',
          v === 'auto' ? 0 : 'auto', h === '0' ? 0 : 'auto',
        ];
        return (
          <div key={i} style={{
            position: 'absolute', top, right, bottom, left, width: size, height: size,
            borderTop: top === 0 ? `1px solid ${color}` : 'none',
            borderBottom: bottom === 0 ? `1px solid ${color}` : 'none',
            borderLeft: left === 0 ? `1px solid ${color}` : 'none',
            borderRight: right === 0 ? `1px solid ${color}` : 'none',
          }} />
        );
      })}
    </>
  );
}

// ─── CarCam status bar — dark, replaces IOSStatusBar for dark frames ───
function CCStatusBar({ time = '9:41', color = CC.ink }) {
  return (
    <div style={{
      display: 'flex', gap: 154, alignItems: 'center', justifyContent: 'center',
      padding: '21px 24px 19px', boxSizing: 'border-box',
      position: 'relative', zIndex: 20, width: '100%',
    }}>
      <div style={{ flex: 1, height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center', paddingTop: 1.5 }}>
        <span style={{
          fontFamily: CC.mono, fontWeight: 500,
          fontSize: 15, lineHeight: '22px', color, letterSpacing: '0.02em',
        }}>{time}</span>
      </div>
      <div style={{ flex: 1, height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, paddingTop: 1, paddingRight: 1 }}>
        <svg width="19" height="12" viewBox="0 0 19 12">
          <rect x="0" y="7.5" width="3.2" height="4.5" rx="0.7" fill={color}/>
          <rect x="4.8" y="5" width="3.2" height="7" rx="0.7" fill={color}/>
          <rect x="9.6" y="2.5" width="3.2" height="9.5" rx="0.7" fill={color}/>
          <rect x="14.4" y="0" width="3.2" height="12" rx="0.7" fill={color}/>
        </svg>
        <svg width="17" height="12" viewBox="0 0 17 12">
          <path d="M8.5 3.2C10.8 3.2 12.9 4.1 14.4 5.6L15.5 4.5C13.7 2.7 11.2 1.5 8.5 1.5C5.8 1.5 3.3 2.7 1.5 4.5L2.6 5.6C4.1 4.1 6.2 3.2 8.5 3.2Z" fill={color}/>
          <path d="M8.5 6.8C9.9 6.8 11.1 7.3 12 8.2L13.1 7.1C11.8 5.9 10.2 5.1 8.5 5.1C6.8 5.1 5.2 5.9 3.9 7.1L5 8.2C5.9 7.3 7.1 6.8 8.5 6.8Z" fill={color}/>
          <circle cx="8.5" cy="10.5" r="1.5" fill={color}/>
        </svg>
        <svg width="27" height="13" viewBox="0 0 27 13">
          <rect x="0.5" y="0.5" width="23" height="12" rx="3.5" stroke={color} strokeOpacity="0.35" fill="none"/>
          <rect x="2" y="2" width="20" height="9" rx="2" fill={color}/>
          <path d="M25 4.5V8.5C25.8 8.2 26.5 7.2 26.5 6.5C26.5 5.8 25.8 4.8 25 4.5Z" fill={color} fillOpacity="0.4"/>
        </svg>
      </div>
    </div>
  );
}

// ─── Recording dot (pulsing) ─────────────────────────────────
function CCRecDot({ size = 8, color = CC.red }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%', background: color,
      boxShadow: `0 0 ${size}px ${color}`,
      animation: 'cc-rec-pulse 1.4s ease-in-out infinite',
    }} />
  );
}

// ─── Global keyframes + font imports ─────────────────────────
function CCGlobalStyles() {
  const css = `
      @keyframes cc-rec-pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.35; }
      }
      @keyframes cc-scan {
        0% { transform: translateY(-100%); }
        100% { transform: translateY(200%); }
      }
      @keyframes cc-blink { 50% { opacity: 0.2; } }
      body { background: ${CC.void}; }
      * { -webkit-font-smoothing: antialiased; }
    `;
  return <style dangerouslySetInnerHTML={{ __html: css }} />;
}

Object.assign(window, {
  CC, CCLabel, CCNum, CCTicks, CCGauge, CCFeedPlaceholder,
  CCCrosshair, CCStatusBar, CCRecDot, CCGlobalStyles,
});
