// Dashboard — 3 variations

// ─── Shared: top bar that replaces the system nav on dashboards ─
function DashTopBar({ right }) {
  return (
    <div style={{
      padding: '56px 20px 0', display: 'flex',
      alignItems: 'center', justifyContent: 'space-between',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        {/* aperture mark */}
        <svg width="18" height="18" viewBox="0 0 18 18">
          <circle cx="9" cy="9" r="8" fill="none" stroke={CC.amber} strokeWidth="1" />
          <circle cx="9" cy="9" r="2" fill={CC.amber} />
        </svg>
        <CCLabel size={10} color={CC.ink}>CARCAM</CCLabel>
      </div>
      {right}
    </div>
  );
}

function DashStatusRight() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <CCRecDot size={6} color={CC.green} />
        <CCLabel size={9} color={CC.green}>ARMED</CCLabel>
      </div>
      <div style={{ width: 1, height: 12, background: CC.ruleHi }} />
      <CCLabel size={9} color={CC.ink3}>48.2 GB</CCLabel>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════
// VARIATION 1 — Cockpit / instrument cluster
// Telemetry-heavy, dense, gauge-driven. The "real dash cam."
// ══════════════════════════════════════════════════════════════
function DashboardCockpit() {
  return (
    <div style={{
      width: '100%', height: '100%', background: CC.void, color: CC.ink,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <DashTopBar right={<DashStatusRight />} />

      {/* trip header */}
      <div style={{ padding: '22px 20px 14px' }}>
        <CCLabel size={9} color={CC.ink4}>TRIP · ACTIVE SESSION</CCLabel>
        <div style={{
          display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
          marginTop: 6,
        }}>
          <div style={{
            fontFamily: CC.sans, fontSize: 24, fontWeight: 300,
            letterSpacing: '-0.02em',
          }}>
            Monday <span style={{ color: CC.ink3 }}>/ Afternoon route</span>
          </div>
          <div style={{ fontFamily: CC.mono, fontSize: 11, color: CC.amber }}>
            T+ 00:24:18
          </div>
        </div>
      </div>

      {/* Big gauge + side stack */}
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr',
        gap: 1, background: CC.rule,
        borderTop: `1px solid ${CC.rule}`, borderBottom: `1px solid ${CC.rule}`,
      }}>
        <div style={{ background: CC.bg, padding: 18, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <CCGauge value={62} max={120} size={168} label="VELOCITY" unit="MPH" sublabel="LIMIT 65" />
        </div>
        <div style={{ background: CC.bg, padding: 18, display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
          <div>
            <CCLabel size={9} color={CC.ink4}>G-FORCE</CCLabel>
            <CCNum value="0.34" unit="g" size={32} color={CC.cyan} weight={200} style={{ marginTop: 4 }} />
            <CCTicks count={16} major={4} height={10} />
          </div>
          <div>
            <CCLabel size={9} color={CC.ink4}>HEADING</CCLabel>
            <CCNum value="048" unit="N-E" size={32} color={CC.ink} weight={200} style={{ marginTop: 4 }} />
          </div>
        </div>
      </div>

      {/* Live feed strip */}
      <div style={{ padding: '16px 20px 8px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          marginBottom: 10,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <CCRecDot size={6} />
            <CCLabel size={9} color={CC.red}>REC · CAM 01</CCLabel>
          </div>
          <CCLabel size={9} color={CC.ink4}>14:32:07.891</CCLabel>
        </div>
        <CCFeedPlaceholder style={{ aspectRatio: '16 / 7' }} label="LIVE FEED · 1440p60">
          <CCCrosshair color={CC.amber} />
          <div style={{ position: 'absolute', bottom: 8, left: 10, display: 'flex', gap: 10 }}>
            <CCLabel size={9} color={CC.ink2}>f/1.8</CCLabel>
            <CCLabel size={9} color={CC.ink2}>ISO 320</CCLabel>
            <CCLabel size={9} color={CC.ink2}>1/120</CCLabel>
          </div>
        </CCFeedPlaceholder>
      </div>

      {/* Telemetry mini-grid */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
        gap: 1, background: CC.rule, margin: '8px 0 0',
        borderTop: `1px solid ${CC.rule}`, borderBottom: `1px solid ${CC.rule}`,
      }}>
        {[
          ['DIST', '14.2', 'mi'],
          ['AVG', '38', 'mph'],
          ['TOP', '71', 'mph'],
          ['FUEL', '3/4', null],
        ].map(([k, v, u]) => (
          <div key={k} style={{ background: CC.bg, padding: '12px 10px' }}>
            <CCLabel size={8} color={CC.ink4}>{k}</CCLabel>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 4 }}>
              <span style={{ fontFamily: CC.mono, fontSize: 18, color: CC.ink, fontWeight: 300 }}>{v}</span>
              {u && <span style={{ fontFamily: CC.mono, fontSize: 9, color: CC.ink4 }}>{u}</span>}
            </div>
          </div>
        ))}
      </div>

      {/* Bottom tab bar */}
      <div style={{ flex: 1 }} />
      <DashTabBar active="live" />
    </div>
  );
}

// ══════════════════════════════════════════════════════════════
// VARIATION 2 — Minimal telemetry stack
// Editorial / Swiss; heavy type, lots of negative space.
// ══════════════════════════════════════════════════════════════
function DashboardMinimal() {
  return (
    <div style={{
      width: '100%', height: '100%', background: CC.void, color: CC.ink,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <DashTopBar right={<DashStatusRight />} />

      <div style={{ padding: '36px 24px 0', flex: 1, display: 'flex', flexDirection: 'column' }}>
        <CCLabel size={10} color={CC.ink4}>TODAY — 14 APR 2026</CCLabel>
        <div style={{
          fontFamily: CC.sans, fontSize: 44, fontWeight: 300,
          letterSpacing: '-0.03em', lineHeight: 1, marginTop: 14, marginBottom: 4,
        }}>
          Ready to<br/>record.
        </div>
        <div style={{ fontFamily: CC.sans, fontSize: 14, color: CC.ink3, marginBottom: 36 }}>
          Last trip ended 16 min ago at 1.4 Maple St.
        </div>

        {/* huge readouts */}
        <div style={{ borderTop: `1px solid ${CC.rule}`, paddingTop: 18, marginBottom: 18 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <CCLabel size={9} color={CC.ink4}>THIS WEEK</CCLabel>
            <CCLabel size={9} color={CC.ink4}>+12% VS LAST</CCLabel>
          </div>
          <div style={{
            fontFamily: CC.mono, fontSize: 64, fontWeight: 200,
            letterSpacing: '-0.04em', lineHeight: 1, marginTop: 12,
            fontVariantNumeric: 'tabular-nums', color: CC.ink,
          }}>
            184.6<span style={{ fontSize: 18, color: CC.ink4, marginLeft: 6 }}>mi</span>
          </div>
          {/* tiny sparkline of daily miles */}
          <svg viewBox="0 0 200 32" style={{ width: '100%', height: 32, marginTop: 14 }} preserveAspectRatio="none">
            {[18, 22, 14, 28, 24, 16, 30].map((v, i) => (
              <rect key={i} x={i * 28 + 1} y={32 - v} width={22} height={v}
                fill={i === 6 ? CC.amber : CC.ruleHi} />
            ))}
          </svg>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6 }}>
            {['M','T','W','T','F','S','S'].map((d, i) => (
              <span key={i} style={{
                fontFamily: CC.mono, fontSize: 9, letterSpacing: '0.2em',
                color: i === 6 ? CC.amber : CC.ink4,
              }}>{d}</span>
            ))}
          </div>
        </div>

        {/* stat grid */}
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20,
          borderTop: `1px solid ${CC.rule}`, paddingTop: 18,
        }}>
          {[
            ['TRIPS', '12'],
            ['CLIPS LOCKED', '3'],
            ['TOP SPEED', '72'],
            ['INCIDENTS', '0'],
          ].map(([k, v]) => (
            <div key={k}>
              <CCLabel size={9} color={CC.ink4}>{k}</CCLabel>
              <div style={{
                fontFamily: CC.mono, fontSize: 28, fontWeight: 300,
                letterSpacing: '-0.02em', color: CC.ink, marginTop: 6,
              }}>{v}</div>
            </div>
          ))}
        </div>

        {/* big REC button */}
        <div style={{ flex: 1 }} />
        <button style={{
          margin: '24px 0 12px',
          padding: '22px', background: CC.amber, color: CC.void,
          border: 'none', fontFamily: CC.mono, fontSize: 13,
          letterSpacing: '0.25em', textTransform: 'uppercase',
          fontWeight: 500, cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 14,
        }}>
          <div style={{ width: 10, height: 10, borderRadius: '50%', background: CC.red }} />
          Start recording
        </button>
      </div>

      <DashTabBar active="home" />
    </div>
  );
}

// ══════════════════════════════════════════════════════════════
// VARIATION 3 — Map-forward with HUD overlay
// ══════════════════════════════════════════════════════════════
function DashboardMap() {
  // procedural "road network" on a dark map
  const mapBg = `
    radial-gradient(ellipse at 30% 40%, ${CC.panel} 0%, ${CC.void} 60%),
    radial-gradient(ellipse at 70% 70%, ${CC.panelHi} 0%, transparent 50%)
  `;

  return (
    <div style={{
      width: '100%', height: '100%', background: CC.void,
      color: CC.ink, display: 'flex', flexDirection: 'column',
      position: 'relative', overflow: 'hidden',
    }}>
      {/* Map canvas (full bleed behind) */}
      <div style={{
        position: 'absolute', inset: 0, background: mapBg,
      }}>
        {/* roads */}
        <svg viewBox="0 0 400 874" preserveAspectRatio="xMidYMid slice" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}>
          <defs>
            <pattern id="dots" width="20" height="20" patternUnits="userSpaceOnUse">
              <circle cx="1" cy="1" r="0.5" fill={CC.ink4} opacity="0.35" />
            </pattern>
          </defs>
          <rect width="400" height="874" fill="url(#dots)" />
          {/* major roads */}
          <path d="M -20 600 Q 100 580 200 500 T 420 320" stroke={CC.ruleHi} strokeWidth="1.5" fill="none" />
          <path d="M 200 -20 Q 220 200 180 420 T 260 900" stroke={CC.ruleHi} strokeWidth="1.5" fill="none" />
          <path d="M -20 200 Q 150 240 250 180 T 420 140" stroke={CC.rule} strokeWidth="1" fill="none" />
          <path d="M 60 900 L 140 620 L 200 500" stroke={CC.rule} strokeWidth="1" fill="none" />
          <path d="M 420 500 L 300 480 L 220 440" stroke={CC.rule} strokeWidth="1" fill="none" />
          {/* active route — amber */}
          <path d="M 60 780 Q 120 700 180 600 Q 230 520 200 420 Q 170 320 220 240" stroke={CC.amber} strokeWidth="2" fill="none" strokeDasharray="0" />
          <path d="M 60 780 Q 120 700 180 600 Q 230 520 200 420" stroke={CC.amber} strokeWidth="3" fill="none" opacity="0.3" />
          {/* destination pin */}
          <circle cx="220" cy="240" r="4" fill={CC.amber} />
          <circle cx="220" cy="240" r="10" fill="none" stroke={CC.amber} strokeWidth="1" opacity="0.5" />
        </svg>

        {/* vehicle marker */}
        <div style={{
          position: 'absolute', left: '15%', top: '57%',
          width: 24, height: 24, transform: 'translate(-50%, -50%) rotate(-35deg)',
        }}>
          <svg width="24" height="24" viewBox="0 0 24 24">
            <polygon points="12,2 20,22 12,18 4,22" fill={CC.cyan} stroke={CC.void} strokeWidth="1" />
          </svg>
        </div>
      </div>

      {/* Top HUD */}
      <div style={{ position: 'relative', zIndex: 2 }}>
        <DashTopBar right={<DashStatusRight />} />
      </div>

      {/* ETA card floating */}
      <div style={{
        position: 'absolute', top: 118, left: 16, right: 16, zIndex: 2,
        background: 'rgba(5,7,10,0.82)',
        backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
        border: `1px solid ${CC.ruleHi}`,
        padding: '14px 16px',
        display: 'flex', alignItems: 'center', gap: 14,
      }}>
        <div style={{ flex: 1 }}>
          <CCLabel size={9} color={CC.amber}>ACTIVE ROUTE</CCLabel>
          <div style={{ fontFamily: CC.sans, fontSize: 18, color: CC.ink, marginTop: 2 }}>
            14.2 mi <span style={{ color: CC.ink3, fontSize: 13 }}>· 28 min</span>
          </div>
          <div style={{ fontFamily: CC.mono, fontSize: 10, color: CC.ink3, marginTop: 4 }}>
            ETA 15:04 · I-280 N
          </div>
        </div>
        <div style={{ width: 1, height: 36, background: CC.rule }} />
        <div>
          <CCLabel size={9} color={CC.ink4}>SPEED</CCLabel>
          <div style={{ fontFamily: CC.mono, fontSize: 22, color: CC.ink, fontWeight: 300, marginTop: 2 }}>
            62<span style={{ fontSize: 10, color: CC.ink4, marginLeft: 3 }}>MPH</span>
          </div>
        </div>
      </div>

      {/* Bottom HUD: mini live feed + quick actions */}
      <div style={{ flex: 1 }} />
      <div style={{
        position: 'relative', zIndex: 2,
        margin: '0 16px 12px', display: 'flex', gap: 10, alignItems: 'stretch',
      }}>
        <CCFeedPlaceholder style={{
          width: 108, height: 72, border: `1px solid ${CC.ruleHi}`,
        }} label="CAM 01">
          <div style={{
            position: 'absolute', top: 4, left: 4, display: 'flex', gap: 4, alignItems: 'center',
          }}>
            <CCRecDot size={5} />
            <CCLabel size={7} color={CC.red}>REC</CCLabel>
          </div>
        </CCFeedPlaceholder>
        <div style={{
          flex: 1, background: 'rgba(5,7,10,0.82)',
          backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
          border: `1px solid ${CC.ruleHi}`,
          display: 'flex', flexDirection: 'column', justifyContent: 'center',
          padding: '10px 14px', gap: 6,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between' }}>
            <CCLabel size={9} color={CC.ink4}>IMPACT GUARD</CCLabel>
            <CCLabel size={9} color={CC.green}>● ARMED</CCLabel>
          </div>
          <div style={{ fontFamily: CC.sans, fontSize: 13, color: CC.ink }}>
            Auto-lock on impact &gt; 1.5g
          </div>
          <div style={{ display: 'flex', gap: 6, marginTop: 2 }}>
            <div style={{
              padding: '4px 8px', border: `1px solid ${CC.ruleHi}`,
              fontFamily: CC.mono, fontSize: 9, color: CC.amber, letterSpacing: '0.15em',
            }}>LOCK CLIP</div>
            <div style={{
              padding: '4px 8px', border: `1px solid ${CC.ruleHi}`,
              fontFamily: CC.mono, fontSize: 9, color: CC.ink3, letterSpacing: '0.15em',
            }}>MARK</div>
          </div>
        </div>
      </div>
      <DashTabBar active="map" />
    </div>
  );
}

// ─── Tab bar ─────────────────────────────────────────────────
function DashTabBar({ active }) {
  const tabs = [
    { key: 'home', label: 'HOME' },
    { key: 'live', label: 'LIVE' },
    { key: 'map', label: 'MAP' },
    { key: 'trips', label: 'TRIPS' },
    { key: 'settings', label: 'SETTINGS' },
  ];
  return (
    <div style={{
      borderTop: `1px solid ${CC.rule}`, background: CC.bg,
      padding: '12px 12px 38px', display: 'flex',
      position: 'relative', zIndex: 3,
    }}>
      {tabs.map(t => (
        <div key={t.key} style={{
          flex: 1, textAlign: 'center', padding: '8px 0',
          fontFamily: CC.mono, fontSize: 9, letterSpacing: '0.2em',
          color: active === t.key ? CC.amber : CC.ink4,
          borderTop: `1px solid ${active === t.key ? CC.amber : 'transparent'}`,
          marginTop: -12, paddingTop: 12,
        }}>{t.label}</div>
      ))}
    </div>
  );
}

Object.assign(window, {
  DashboardCockpit, DashboardMinimal, DashboardMap, DashTabBar,
});
