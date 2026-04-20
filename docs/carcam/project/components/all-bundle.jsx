
// ═══════ components/carcam-tokens.jsx ═══════
// CarCam design tokens + shared primitives
// Technical instrument-cluster aesthetic.

const CC = {
  // surfaces
  void: '#05070A',
  bg: '#0B0D11',
  panel: '#101419',
  panelHi: '#161B22',
  rule: 'rgba(255,255,255,0.06)',
  ruleHi: 'rgba(255,255,255,0.12)',

  // text
  ink: '#F2F3F5',
  ink2: 'rgba(242,243,245,0.72)',
  ink3: 'rgba(242,243,245,0.48)',
  ink4: 'rgba(242,243,245,0.28)',

  // signal — amber primary, cyan secondary, red for REC
  amber: 'oklch(0.82 0.16 78)',
  amberDim: 'oklch(0.55 0.12 78)',
  cyan: 'oklch(0.82 0.11 210)',
  cyanDim: 'oklch(0.55 0.08 210)',
  red: 'oklch(0.66 0.22 25)',
  green: 'oklch(0.78 0.14 150)',

  // type
  sans: '"Inter Tight", -apple-system, system-ui, sans-serif',
  mono: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace',
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


// ═══════ components/screens-onboarding.jsx ═══════
// Onboarding — 4 screens
// Aesthetic: technical welcome, no marketing fluff.

function OnboardFrame({ children, step = 1, total = 4 }) {
  return (
    <div style={{
      width: '100%', height: '100%',
      background: CC.void, color: CC.ink,
      display: 'flex', flexDirection: 'column',
      position: 'relative', overflow: 'hidden',
    }}>
      {/* corner identifiers */}
      <div style={{
        position: 'absolute', top: 54, left: 20, right: 20,
        display: 'flex', justifyContent: 'space-between', zIndex: 2,
      }}>
        <CCLabel size={9}>CARCAM / v4.2</CCLabel>
        <CCLabel size={9}>
          <span style={{ color: CC.amber }}>{String(step).padStart(2, '0')}</span>
          <span style={{ color: CC.ink4 }}> / {String(total).padStart(2, '0')}</span>
        </CCLabel>
      </div>
      {children}
      {/* step indicator */}
      <div style={{
        position: 'absolute', bottom: 54, left: 20, right: 20,
        display: 'flex', gap: 4, zIndex: 2,
      }}>
        {Array.from({ length: total }).map((_, i) => (
          <div key={i} style={{
            flex: 1, height: 2,
            background: i < step ? CC.amber : CC.rule,
          }} />
        ))}
      </div>
    </div>
  );
}

function OnboardButton({ children, primary, onClick }) {
  return (
    <button onClick={onClick} style={{
      width: '100%', padding: '18px', border: 'none',
      background: primary ? CC.amber : 'transparent',
      color: primary ? CC.void : CC.ink,
      fontFamily: CC.mono, fontSize: 12, letterSpacing: '0.2em',
      textTransform: 'uppercase', fontWeight: 500,
      cursor: 'pointer',
      border: primary ? 'none' : `1px solid ${CC.ruleHi}`,
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12,
    }}>
      {children}
    </button>
  );
}

// ─── Screen 1: Welcome / brand ───────────────────────────────
function Onboard01() {
  return (
    <OnboardFrame step={1}>
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column',
        justifyContent: 'center', padding: '0 28px',
      }}>
        {/* logo mark — a stylized aperture/lens */}
        <div style={{ marginBottom: 48, position: 'relative' }}>
          <svg width="96" height="96" viewBox="0 0 96 96">
            {/* outer ring */}
            <circle cx="48" cy="48" r="44" fill="none" stroke={CC.ink3} strokeWidth="1" />
            <circle cx="48" cy="48" r="36" fill="none" stroke={CC.amber} strokeWidth="1" />
            {/* aperture blades */}
            {[0, 60, 120, 180, 240, 300].map(a => (
              <line key={a} x1="48" y1="48" x2={48 + 36 * Math.cos(a * Math.PI / 180)}
                y2={48 + 36 * Math.sin(a * Math.PI / 180)}
                stroke={CC.ruleHi} strokeWidth="1" />
            ))}
            <circle cx="48" cy="48" r="10" fill="none" stroke={CC.amber} strokeWidth="1.5" />
            <circle cx="48" cy="48" r="2" fill={CC.amber} />
          </svg>
        </div>
        <div style={{
          fontFamily: CC.sans, fontSize: 44, fontWeight: 300,
          letterSpacing: '-0.03em', lineHeight: 1, marginBottom: 16,
        }}>
          Your phone.<br/>
          Your witness.
        </div>
        <div style={{
          fontFamily: CC.sans, fontSize: 15, color: CC.ink2,
          lineHeight: 1.5, marginBottom: 48, maxWidth: 320,
        }}>
          A continuously recording dash cam. Loop captures, automatic
          incident locking, GPS telemetry — all on-device.
        </div>

        {/* spec grid */}
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
          borderTop: `1px solid ${CC.rule}`, borderBottom: `1px solid ${CC.rule}`,
          marginBottom: 40,
        }}>
          {[
            ['1440p', 'Capture'],
            ['60fps', 'Framerate'],
            ['H.265', 'Codec'],
          ].map(([v, l]) => (
            <div key={l} style={{ padding: '16px 0', borderLeft: `1px solid ${CC.rule}`, paddingLeft: 12 }}>
              <div style={{ fontFamily: CC.mono, fontSize: 18, color: CC.ink, marginBottom: 4 }}>{v}</div>
              <CCLabel size={9} color={CC.ink4}>{l}</CCLabel>
            </div>
          ))}
        </div>
      </div>

      <div style={{ padding: '0 20px 90px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <OnboardButton primary>
          Begin setup
          <svg width="14" height="10" viewBox="0 0 14 10">
            <path d="M0 5h12M8 1l4 4-4 4" fill="none" stroke={CC.void} strokeWidth="1.5"/>
          </svg>
        </OnboardButton>
      </div>
    </OnboardFrame>
  );
}

// ─── Screen 2: Permissions ────────────────────────────────────
function Onboard02() {
  const perms = [
    { key: 'CAM', label: 'Camera', sub: 'Required for video capture.', status: 'granted' },
    { key: 'LOC', label: 'Location (Always)', sub: 'GPS, speed, and trip geofencing.', status: 'granted' },
    { key: 'MOT', label: 'Motion & Orientation', sub: 'G-force and impact detection.', status: 'pending' },
    { key: 'MIC', label: 'Microphone', sub: 'Optional — for voice memos.', status: 'skip' },
    { key: 'PHO', label: 'Photos', sub: 'To save locked clips to library.', status: 'pending' },
  ];
  return (
    <OnboardFrame step={2}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '88px 28px 0' }}>
        <CCLabel style={{ marginBottom: 8 }} color={CC.amber}>02 — Authorizations</CCLabel>
        <div style={{
          fontFamily: CC.sans, fontSize: 30, fontWeight: 300,
          letterSpacing: '-0.02em', lineHeight: 1.1, marginBottom: 36,
        }}>
          Grant the sensors<br/>CarCam needs.
        </div>

        <div style={{ borderTop: `1px solid ${CC.rule}` }}>
          {perms.map(p => (
            <div key={p.key} style={{
              display: 'flex', alignItems: 'center', gap: 16,
              padding: '18px 0', borderBottom: `1px solid ${CC.rule}`,
            }}>
              <div style={{
                fontFamily: CC.mono, fontSize: 10, color: CC.ink3,
                width: 32, letterSpacing: '0.1em',
              }}>{p.key}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: CC.sans, fontSize: 15, color: CC.ink, marginBottom: 2 }}>{p.label}</div>
                <div style={{ fontFamily: CC.sans, fontSize: 12, color: CC.ink3 }}>{p.sub}</div>
              </div>
              <div style={{
                fontFamily: CC.mono, fontSize: 9, letterSpacing: '0.2em',
                padding: '4px 8px',
                color: p.status === 'granted' ? CC.green : p.status === 'pending' ? CC.amber : CC.ink4,
                border: `1px solid ${p.status === 'granted' ? CC.green : p.status === 'pending' ? CC.amber : CC.ink4}`,
              }}>
                {p.status === 'granted' ? '✓ OK' : p.status === 'pending' ? 'AUTH' : 'SKIP'}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div style={{ padding: '24px 20px 90px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <OnboardButton primary>Authorize all</OnboardButton>
        <OnboardButton>Configure individually</OnboardButton>
      </div>
    </OnboardFrame>
  );
}

// ─── Screen 3: Mount calibration ─────────────────────────────
function Onboard03() {
  return (
    <OnboardFrame step={3}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '88px 28px 0' }}>
        <CCLabel style={{ marginBottom: 8 }} color={CC.amber}>03 — Calibration</CCLabel>
        <div style={{
          fontFamily: CC.sans, fontSize: 30, fontWeight: 300,
          letterSpacing: '-0.02em', lineHeight: 1.1, marginBottom: 12,
        }}>
          Level your mount.
        </div>
        <div style={{ fontFamily: CC.sans, fontSize: 13, color: CC.ink3, marginBottom: 28 }}>
          Place phone in landscape on the windshield. Hold still.
        </div>

        {/* Horizon calibrator */}
        <div style={{
          aspectRatio: '1 / 1', position: 'relative',
          border: `1px solid ${CC.rule}`, margin: '0 auto', width: '100%',
          background: `radial-gradient(circle at center, ${CC.panelHi} 0%, ${CC.void} 70%)`,
        }}>
          <CCCrosshair color={CC.amber} size={14} />
          {/* crosshair lines */}
          <div style={{ position: 'absolute', top: '50%', left: 0, right: 0, height: 1, background: CC.rule }} />
          <div style={{ position: 'absolute', left: '50%', top: 0, bottom: 0, width: 1, background: CC.rule }} />
          {/* tilted horizon — indicator */}
          <div style={{
            position: 'absolute', top: '50%', left: '10%', right: '10%',
            height: 1, background: CC.amber, transform: 'translateY(-50%) rotate(-3.2deg)',
            transformOrigin: 'center',
          }} />
          {/* bubble level */}
          <div style={{
            position: 'absolute', top: '50%', left: '50%',
            width: 28, height: 28, borderRadius: '50%',
            transform: 'translate(-40%, -50%)',
            border: `1px solid ${CC.amber}`,
            boxShadow: `0 0 12px ${CC.amber}`,
          }} />
          {/* angle readout */}
          <div style={{
            position: 'absolute', bottom: 12, left: 12, display: 'flex', gap: 16,
          }}>
            <div>
              <CCLabel size={9} color={CC.ink4}>PITCH</CCLabel>
              <div style={{ fontFamily: CC.mono, fontSize: 16, color: CC.ink }}>+1.4°</div>
            </div>
            <div>
              <CCLabel size={9} color={CC.ink4}>ROLL</CCLabel>
              <div style={{ fontFamily: CC.mono, fontSize: 16, color: CC.amber }}>−3.2°</div>
            </div>
          </div>
          <div style={{ position: 'absolute', bottom: 12, right: 12 }}>
            <CCLabel size={9} color={CC.amber}>ADJUSTING…</CCLabel>
          </div>
        </div>

        {/* feedback hint */}
        <div style={{
          marginTop: 24, padding: 14,
          border: `1px solid ${CC.ruleHi}`, borderLeft: `2px solid ${CC.amber}`,
          fontFamily: CC.mono, fontSize: 11, color: CC.ink2, lineHeight: 1.5,
        }}>
          ROTATE PHONE CLOCKWISE 3.2° TO LEVEL HORIZON.
        </div>
      </div>

      <div style={{ padding: '24px 20px 90px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <OnboardButton primary>Save calibration</OnboardButton>
        <OnboardButton>Skip for now</OnboardButton>
      </div>
    </OnboardFrame>
  );
}

// ─── Screen 4: Ready ─────────────────────────────────────────
function Onboard04() {
  return (
    <OnboardFrame step={4}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '88px 28px 0' }}>
        <CCLabel style={{ marginBottom: 8 }} color={CC.green}>04 — System ready</CCLabel>
        <div style={{
          fontFamily: CC.sans, fontSize: 36, fontWeight: 300,
          letterSpacing: '-0.02em', lineHeight: 1, marginBottom: 32,
        }}>
          All systems<br/>nominal.
        </div>

        {/* system check list */}
        <div style={{ borderTop: `1px solid ${CC.rule}`, marginBottom: 24 }}>
          {[
            ['Camera', '1440p / 60'],
            ['GPS lock', '11 sats'],
            ['Accelerometer', '±4g range'],
            ['Storage', '48.2 GB free'],
            ['Battery', '87% · charging'],
          ].map(([k, v]) => (
            <div key={k} style={{
              display: 'flex', alignItems: 'center',
              padding: '12px 0', borderBottom: `1px solid ${CC.rule}`,
              fontFamily: CC.mono, fontSize: 12,
            }}>
              <span style={{ color: CC.green, marginRight: 12 }}>●</span>
              <span style={{ flex: 1, color: CC.ink2 }}>{k}</span>
              <span style={{ color: CC.ink }}>{v}</span>
            </div>
          ))}
        </div>

        {/* ascii-ish diagnostic */}
        <div style={{
          fontFamily: CC.mono, fontSize: 10, color: CC.ink4,
          lineHeight: 1.6, padding: 14, background: CC.panel,
          border: `1px solid ${CC.rule}`,
        }}>
          &gt; handshake.sensor_bus ..... <span style={{ color: CC.green }}>OK</span><br/>
          &gt; calibrate.horizon ....... <span style={{ color: CC.green }}>OK</span><br/>
          &gt; init.loop_buffer 90min .. <span style={{ color: CC.green }}>OK</span><br/>
          &gt; standby.impact_detect ... <span style={{ color: CC.amber }}>ARMED</span>
        </div>
      </div>

      <div style={{ padding: '24px 20px 90px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <OnboardButton primary>
          Start recording
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <div style={{ width: 6, height: 6, borderRadius: '50%', background: CC.red }} />
          </div>
        </OnboardButton>
      </div>
    </OnboardFrame>
  );
}

Object.assign(window, { Onboard01, Onboard02, Onboard03, Onboard04 });


// ═══════ components/screens-dashboard.jsx ═══════
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


// ═══════ components/screens-live.jsx ═══════
// Live cam view — full-bleed camera in landscape with telemetry HUD overlay.
// This is the "hero" screen. Shown in landscape orientation.

function LiveCamView() {
  return (
    <div style={{
      // landscape: wider than tall. The device frame is portrait 402x874;
      // we render rotated content inside.
      width: '100%', height: '100%', background: CC.void,
      position: 'relative', overflow: 'hidden',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      {/* rotated container: 874x402 landscape inside a 402x874 portrait frame */}
      <div style={{
        width: 874, height: 402, position: 'relative',
        transform: 'rotate(90deg)',
        transformOrigin: 'center',
      }}>
        {/* full-bleed feed */}
        <CCFeedPlaceholder style={{ position: 'absolute', inset: 0 }} label="LIVE FEED · 1440p60 · H.265">
          {/* scan line */}
          <div style={{
            position: 'absolute', inset: 0, pointerEvents: 'none',
            overflow: 'hidden',
          }}>
            <div style={{
              position: 'absolute', left: 0, right: 0, height: 60,
              background: `linear-gradient(to bottom, transparent, ${CC.amber}11, transparent)`,
              animation: 'cc-scan 6s linear infinite',
            }} />
          </div>
        </CCFeedPlaceholder>

        {/* Full HUD overlay */}
        <LiveHUD />
      </div>
    </div>
  );
}

function LiveHUD() {
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      {/* Top strip — rec state, timecode, location */}
      <div style={{
        position: 'absolute', top: 14, left: 22, right: 22,
        display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10,
          background: 'rgba(5,7,10,0.55)', padding: '8px 12px',
          border: `1px solid ${CC.ruleHi}`,
        }}>
          <CCRecDot size={8} />
          <CCLabel size={10} color={CC.red}>REC</CCLabel>
          <div style={{ width: 1, height: 12, background: CC.ruleHi }} />
          <div style={{ fontFamily: CC.mono, fontSize: 13, color: CC.ink, fontVariantNumeric: 'tabular-nums' }}>
            00:24:18.34
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4,
          background: 'rgba(5,7,10,0.55)', padding: '8px 12px',
          border: `1px solid ${CC.ruleHi}`,
        }}>
          <CCLabel size={9} color={CC.ink3}>37.7749° N · 122.4194° W</CCLabel>
          <CCLabel size={9} color={CC.ink3}>I-280 N · SAN FRANCISCO</CCLabel>
        </div>
      </div>

      {/* LEFT cluster — velocity gauge */}
      <div style={{
        position: 'absolute', top: 60, left: 22, bottom: 60,
        display: 'flex', flexDirection: 'column', gap: 12, justifyContent: 'center',
      }}>
        <div style={{
          background: 'rgba(5,7,10,0.55)', border: `1px solid ${CC.ruleHi}`,
          padding: 14, position: 'relative',
        }}>
          <CCCrosshair color={CC.ink4} size={6} />
          <CCGauge value={62} max={120} size={160} label="VELOCITY" unit="MPH" sublabel="LIMIT 65" />
        </div>
      </div>

      {/* RIGHT cluster — stacked telemetry */}
      <div style={{
        position: 'absolute', top: 60, right: 22, bottom: 60,
        display: 'flex', flexDirection: 'column', gap: 12, justifyContent: 'center',
      }}>
        {/* G-force meter */}
        <div style={{
          background: 'rgba(5,7,10,0.55)', border: `1px solid ${CC.ruleHi}`,
          padding: 12, width: 180, position: 'relative',
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
            <CCLabel size={9} color={CC.ink4}>G-FORCE</CCLabel>
            <CCLabel size={9} color={CC.cyan}>PEAK 0.8</CCLabel>
          </div>
          {/* 2d g-force target */}
          <div style={{ position: 'relative', width: '100%', aspectRatio: '1 / 1' }}>
            {/* concentric rings */}
            {[1, 0.66, 0.33].map((r, i) => (
              <div key={i} style={{
                position: 'absolute', inset: `${(1 - r) * 50}%`,
                borderRadius: '50%', border: `1px solid ${CC.rule}`,
              }} />
            ))}
            {/* crosshair */}
            <div style={{ position: 'absolute', left: '50%', top: 0, bottom: 0, width: 1, background: CC.rule }} />
            <div style={{ position: 'absolute', top: '50%', left: 0, right: 0, height: 1, background: CC.rule }} />
            {/* dot */}
            <div style={{
              position: 'absolute', left: '60%', top: '42%',
              width: 6, height: 6, borderRadius: '50%', background: CC.cyan,
              boxShadow: `0 0 10px ${CC.cyan}`, transform: 'translate(-50%, -50%)',
            }} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6 }}>
            <span style={{ fontFamily: CC.mono, fontSize: 10, color: CC.cyan }}>X +0.34</span>
            <span style={{ fontFamily: CC.mono, fontSize: 10, color: CC.cyan }}>Y −0.12</span>
          </div>
        </div>

        {/* heading + altitude */}
        <div style={{
          background: 'rgba(5,7,10,0.55)', border: `1px solid ${CC.ruleHi}`,
          padding: 12, width: 180,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
            <CCLabel size={9} color={CC.ink4}>HEADING</CCLabel>
            <CCLabel size={9} color={CC.ink4}>ALT</CCLabel>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <div style={{ fontFamily: CC.mono, fontSize: 22, color: CC.ink, fontWeight: 300 }}>
              048<span style={{ fontSize: 10, color: CC.ink4, marginLeft: 4 }}>NE</span>
            </div>
            <div style={{ fontFamily: CC.mono, fontSize: 14, color: CC.ink2 }}>
              286<span style={{ fontSize: 9, color: CC.ink4, marginLeft: 2 }}>FT</span>
            </div>
          </div>
        </div>
      </div>

      {/* CENTER: subtle AR-style horizon + reticle */}
      <div style={{
        position: 'absolute', top: '50%', left: '50%',
        transform: 'translate(-50%, -50%)',
        width: 120, height: 60, pointerEvents: 'none',
      }}>
        {/* horizon line */}
        <div style={{
          position: 'absolute', top: '50%', left: 0, right: 0, height: 1,
          background: CC.amber, opacity: 0.4,
        }} />
        {/* center bracket */}
        <div style={{
          position: 'absolute', top: 'calc(50% - 4px)', left: '50%',
          transform: 'translateX(-50%)', width: 40, height: 8,
          borderLeft: `1px solid ${CC.amber}`,
          borderRight: `1px solid ${CC.amber}`,
        }} />
        {/* tilt indicator */}
        <div style={{
          position: 'absolute', top: -20, left: '50%', transform: 'translateX(-50%)',
          fontFamily: CC.mono, fontSize: 10, color: CC.amber,
        }}>
          ◆ LVL
        </div>
      </div>

      {/* BOTTOM strip — action controls + timeline */}
      <div style={{
        position: 'absolute', bottom: 14, left: 22, right: 22,
        display: 'flex', alignItems: 'center', gap: 12,
        pointerEvents: 'auto',
      }}>
        {/* timecode timeline */}
        <div style={{
          flex: 1, background: 'rgba(5,7,10,0.55)',
          border: `1px solid ${CC.ruleHi}`, padding: '10px 14px',
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
            <CCLabel size={9} color={CC.ink3}>LOOP BUFFER · 90 MIN</CCLabel>
            <CCLabel size={9} color={CC.amber}>24:18 / 90:00</CCLabel>
          </div>
          <div style={{ position: 'relative', height: 6, background: CC.rule }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '27%', background: CC.amber }} />
            {/* locked-clip markers */}
            <div style={{ position: 'absolute', left: '12%', top: -2, bottom: -2, width: 2, background: CC.red }} />
            <div style={{ position: 'absolute', left: '19%', top: -2, bottom: -2, width: 2, background: CC.red }} />
          </div>
        </div>

        {/* Big LOCK button */}
        <button style={{
          padding: '14px 20px', background: 'transparent',
          border: `1px solid ${CC.amber}`, color: CC.amber,
          fontFamily: CC.mono, fontSize: 11, letterSpacing: '0.2em',
          textTransform: 'uppercase', cursor: 'pointer',
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <svg width="12" height="14" viewBox="0 0 12 14">
            <rect x="1" y="6" width="10" height="7" fill="none" stroke={CC.amber} strokeWidth="1.5"/>
            <path d="M3 6V4a3 3 0 016 0v2" fill="none" stroke={CC.amber} strokeWidth="1.5"/>
          </svg>
          LOCK
        </button>

        {/* Big STOP button */}
        <button style={{
          padding: '14px 20px', background: CC.red, color: CC.ink,
          border: 'none',
          fontFamily: CC.mono, fontSize: 11, letterSpacing: '0.2em',
          textTransform: 'uppercase', cursor: 'pointer',
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <div style={{ width: 10, height: 10, background: CC.ink }} />
          STOP
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { LiveCamView, LiveHUD });


// ═══════ components/screens-other.jsx ═══════
// Settings + Trip history + Incident playback screens

// ─────────────────────────────────────────────────────────────
// SETTINGS
// ─────────────────────────────────────────────────────────────
function SettingsRow({ label, value, onToggle, toggle, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center',
      padding: '14px 20px',
      borderBottom: last ? 'none' : `1px solid ${CC.rule}`,
    }}>
      <div style={{ flex: 1, fontFamily: CC.sans, fontSize: 14, color: CC.ink }}>
        {label}
      </div>
      {toggle !== undefined ? (
        <div style={{
          width: 36, height: 20, borderRadius: 0,
          background: toggle ? CC.amber : CC.rule,
          position: 'relative', cursor: 'pointer',
        }}>
          <div style={{
            position: 'absolute', top: 2, left: toggle ? 18 : 2,
            width: 16, height: 16,
            background: toggle ? CC.void : CC.ink3,
            transition: 'left 0.15s',
          }} />
        </div>
      ) : (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontFamily: CC.mono, fontSize: 12, color: CC.amber }}>{value}</span>
          <svg width="6" height="10" viewBox="0 0 6 10">
            <path d="M1 1l4 4-4 4" fill="none" stroke={CC.ink4} strokeWidth="1.2" />
          </svg>
        </div>
      )}
    </div>
  );
}

function SettingsSection({ title, code, children }) {
  return (
    <div style={{ marginBottom: 24 }}>
      <div style={{
        display: 'flex', justifyContent: 'space-between',
        padding: '0 20px 8px',
      }}>
        <CCLabel size={9} color={CC.ink3}>{title}</CCLabel>
        <CCLabel size={9} color={CC.ink4}>{code}</CCLabel>
      </div>
      <div style={{ borderTop: `1px solid ${CC.rule}`, borderBottom: `1px solid ${CC.rule}`, background: CC.bg }}>
        {children}
      </div>
    </div>
  );
}

function SettingsScreen() {
  return (
    <div style={{
      width: '100%', height: '100%', background: CC.void, color: CC.ink,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <DashTopBar />

      <div style={{ padding: '24px 20px 14px' }}>
        <CCLabel size={9} color={CC.ink4}>SYSTEM / PREFERENCES</CCLabel>
        <div style={{
          fontFamily: CC.sans, fontSize: 32, fontWeight: 300,
          letterSpacing: '-0.02em', marginTop: 6,
        }}>Settings</div>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', paddingBottom: 20 }}>
        <SettingsSection title="CAPTURE" code="§01">
          <SettingsRow label="Resolution" value="1440p · 60fps" />
          <SettingsRow label="Codec" value="HEVC / H.265" />
          <SettingsRow label="Loop length" value="90 min" />
          <SettingsRow label="Bitrate" value="25 Mbps" last />
        </SettingsSection>

        <SettingsSection title="INCIDENT DETECTION" code="§02">
          <SettingsRow label="Auto-lock on impact" toggle={true} />
          <SettingsRow label="Impact threshold" value="1.5 g" />
          <SettingsRow label="Parking sentry" toggle={true} />
          <SettingsRow label="Hard-brake detection" toggle={false} last />
        </SettingsSection>

        <SettingsSection title="OVERLAY" code="§03">
          <SettingsRow label="Show speed on clip" toggle={true} />
          <SettingsRow label="Show GPS coordinates" toggle={true} />
          <SettingsRow label="Show G-force trace" toggle={false} />
          <SettingsRow label="Watermark" value="Off" last />
        </SettingsSection>

        <SettingsSection title="STORAGE" code="§04">
          <SettingsRow label="Used" value="12.8 / 64 GB" />
          <SettingsRow label="Auto-export to Photos" toggle={true} />
          <SettingsRow label="iCloud backup" toggle={false} last />
        </SettingsSection>

        {/* storage bar */}
        <div style={{ padding: '0 20px', marginBottom: 28 }}>
          <div style={{ height: 4, background: CC.panel, position: 'relative' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '20%', background: CC.amber }} />
            <div style={{ position: 'absolute', left: '20%', top: 0, bottom: 0, width: '4%', background: CC.red }} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6 }}>
            <span style={{ fontFamily: CC.mono, fontSize: 9, color: CC.amber }}>■ LOOP 12.8GB</span>
            <span style={{ fontFamily: CC.mono, fontSize: 9, color: CC.red }}>■ LOCKED 2.6GB</span>
            <span style={{ fontFamily: CC.mono, fontSize: 9, color: CC.ink4 }}>□ FREE 48.6GB</span>
          </div>
        </div>
      </div>

      <DashTabBar active="settings" />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// TRIP HISTORY
// ─────────────────────────────────────────────────────────────
function TripRow({ date, route, stats, locked, active }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: '56px 1fr auto',
      gap: 12, padding: '16px 20px',
      borderBottom: `1px solid ${CC.rule}`,
      alignItems: 'center',
      background: active ? CC.panel : 'transparent',
    }}>
      <div>
        <div style={{ fontFamily: CC.mono, fontSize: 22, color: CC.ink, fontWeight: 300, lineHeight: 1 }}>{date.day}</div>
        <CCLabel size={9} color={CC.ink4} style={{ marginTop: 2 }}>{date.month}</CCLabel>
      </div>
      <div>
        <div style={{ fontFamily: CC.sans, fontSize: 15, color: CC.ink, marginBottom: 4 }}>{route}</div>
        <div style={{ fontFamily: CC.mono, fontSize: 10, color: CC.ink3, letterSpacing: '0.08em' }}>
          {stats}
        </div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end' }}>
        {locked > 0 && (
          <div style={{
            padding: '2px 6px', border: `1px solid ${CC.red}`,
            fontFamily: CC.mono, fontSize: 9, color: CC.red, letterSpacing: '0.15em',
          }}>◉ {locked}</div>
        )}
        <svg width="6" height="10" viewBox="0 0 6 10">
          <path d="M1 1l4 4-4 4" fill="none" stroke={CC.ink4} strokeWidth="1.2" />
        </svg>
      </div>
    </div>
  );
}

function TripsScreen() {
  const trips = [
    { date: { day: 14, month: 'APR' }, route: 'Home → Office', stats: '14.2 MI · 28 MIN · AVG 38 MPH', locked: 1, active: true },
    { date: { day: 13, month: 'APR' }, route: 'Office → Home', stats: '14.8 MI · 34 MIN · AVG 32 MPH', locked: 0 },
    { date: { day: 13, month: 'APR' }, route: 'Home → Grocery', stats: '3.1 MI · 11 MIN · AVG 24 MPH', locked: 0 },
    { date: { day: 12, month: 'APR' }, route: 'Weekend loop', stats: '62.4 MI · 01:42 · AVG 48 MPH', locked: 2 },
    { date: { day: 11, month: 'APR' }, route: 'Airport run', stats: '28.0 MI · 42 MIN · AVG 52 MPH', locked: 0 },
    { date: { day: 10, month: 'APR' }, route: 'Home → Office', stats: '14.2 MI · 30 MIN · AVG 36 MPH', locked: 0 },
  ];
  return (
    <div style={{
      width: '100%', height: '100%', background: CC.void, color: CC.ink,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <DashTopBar right={<CCLabel size={9} color={CC.ink3}>12 THIS WEEK</CCLabel>} />
      <div style={{ padding: '24px 20px 16px' }}>
        <CCLabel size={9} color={CC.ink4}>ARCHIVE / SESSIONS</CCLabel>
        <div style={{
          fontFamily: CC.sans, fontSize: 32, fontWeight: 300,
          letterSpacing: '-0.02em', marginTop: 6,
        }}>Trips</div>
      </div>

      {/* summary strip */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
        gap: 1, background: CC.rule,
        borderTop: `1px solid ${CC.rule}`, borderBottom: `1px solid ${CC.rule}`,
      }}>
        {[
          ['TOTAL', '184.6', 'MI'],
          ['TIME', '06:42', 'HR'],
          ['LOCKED', '3', 'CLIPS'],
        ].map(([k, v, u]) => (
          <div key={k} style={{ background: CC.bg, padding: '12px 14px' }}>
            <CCLabel size={8} color={CC.ink4}>{k}</CCLabel>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 4 }}>
              <span style={{ fontFamily: CC.mono, fontSize: 20, color: CC.ink, fontWeight: 300 }}>{v}</span>
              <span style={{ fontFamily: CC.mono, fontSize: 9, color: CC.ink4, letterSpacing: '0.15em' }}>{u}</span>
            </div>
          </div>
        ))}
      </div>

      <div style={{ flex: 1, overflowY: 'auto' }}>
        {trips.map((t, i) => <TripRow key={i} {...t} />)}
      </div>

      <DashTabBar active="trips" />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// INCIDENT PLAYBACK
// ─────────────────────────────────────────────────────────────
function IncidentScreen() {
  return (
    <div style={{
      width: '100%', height: '100%', background: CC.void, color: CC.ink,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <DashTopBar right={
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <CCRecDot size={6} color={CC.red} />
          <CCLabel size={9} color={CC.red}>LOCKED</CCLabel>
        </div>
      } />
      <div style={{ padding: '22px 20px 14px' }}>
        <CCLabel size={9} color={CC.red}>INCIDENT · LOCKED CLIP</CCLabel>
        <div style={{
          fontFamily: CC.sans, fontSize: 24, fontWeight: 300,
          letterSpacing: '-0.02em', marginTop: 6, lineHeight: 1.2,
        }}>Impact event — 1.8g lateral</div>
        <div style={{ fontFamily: CC.mono, fontSize: 11, color: CC.ink3, marginTop: 6 }}>
          14 APR · 14:32:08 · I-280 N · MM 48.2
        </div>
      </div>

      {/* Video window */}
      <div style={{ padding: '0 20px 12px' }}>
        <CCFeedPlaceholder style={{
          aspectRatio: '16 / 9', border: `1px solid ${CC.ruleHi}`,
        }} label="CLIP 0023 · 00:18">
          <CCCrosshair color={CC.red} />
          {/* play indicator */}
          <div style={{
            position: 'absolute', top: 10, left: 12, display: 'flex', gap: 10, alignItems: 'center',
          }}>
            <CCRecDot size={6} color={CC.red} />
            <CCLabel size={9} color={CC.red}>REVIEW · 0.5×</CCLabel>
          </div>
          <div style={{
            position: 'absolute', top: 10, right: 12,
            fontFamily: CC.mono, fontSize: 11, color: CC.ink,
          }}>00:08 / 00:18</div>
          {/* impact marker */}
          <div style={{
            position: 'absolute', bottom: 12, right: 12,
            padding: '4px 8px', border: `1px solid ${CC.red}`,
            fontFamily: CC.mono, fontSize: 9, color: CC.red, letterSpacing: '0.15em',
          }}>IMPACT +0.8s</div>
        </CCFeedPlaceholder>

        {/* scrubber with impact markers */}
        <div style={{ marginTop: 10, position: 'relative', height: 34 }}>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 14, height: 6, background: CC.panel }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '44%', background: CC.ink2 }} />
          </div>
          {/* impact marker at ~44% */}
          <div style={{
            position: 'absolute', left: '44%', top: 0, bottom: 0, width: 2, background: CC.red,
            boxShadow: `0 0 8px ${CC.red}`,
          }} />
          <div style={{ position: 'absolute', left: '8%', top: 12, width: 2, height: 10, background: CC.amber }} />
          <div style={{ position: 'absolute', left: '78%', top: 12, width: 2, height: 10, background: CC.amber }} />
        </div>
      </div>

      {/* Telemetry trace */}
      <div style={{ padding: '0 20px', marginBottom: 10 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
          <CCLabel size={9} color={CC.ink3}>TELEMETRY — G-FORCE</CCLabel>
          <CCLabel size={9} color={CC.red}>PEAK 1.82g @ T+8.4s</CCLabel>
        </div>
        <svg viewBox="0 0 320 60" style={{ width: '100%', height: 60, display: 'block', background: CC.bg, border: `1px solid ${CC.rule}` }}>
          {/* grid */}
          {[15, 30, 45].map(y => <line key={y} x1="0" y1={y} x2="320" y2={y} stroke={CC.rule} />)}
          {/* trace */}
          <polyline points="0,32 20,34 40,28 60,30 80,26 100,32 120,38 140,20 160,8 180,52 200,40 220,36 240,32 260,30 280,32 300,30 320,32"
            fill="none" stroke={CC.amber} strokeWidth="1.5" />
          {/* peak marker */}
          <line x1="160" y1="0" x2="160" y2="60" stroke={CC.red} strokeDasharray="2 2" />
          <circle cx="160" cy="8" r="3" fill={CC.red} />
        </svg>
      </div>

      {/* Stat strip */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
        gap: 1, background: CC.rule,
        borderTop: `1px solid ${CC.rule}`, borderBottom: `1px solid ${CC.rule}`,
        margin: '6px 0',
      }}>
        {[
          ['SPEED', '58', 'MPH'],
          ['PEAK G', '1.82', 'G'],
          ['BRAKE', 'HARD'],
          ['LANE', 'CENTER'],
        ].map(([k, v, u]) => (
          <div key={k} style={{ background: CC.bg, padding: '10px 12px' }}>
            <CCLabel size={8} color={CC.ink4}>{k}</CCLabel>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 3, marginTop: 3 }}>
              <span style={{ fontFamily: CC.mono, fontSize: 15, color: k === 'PEAK G' ? CC.red : CC.ink }}>{v}</span>
              {u && <span style={{ fontFamily: CC.mono, fontSize: 8, color: CC.ink4 }}>{u}</span>}
            </div>
          </div>
        ))}
      </div>

      <div style={{ flex: 1 }} />

      {/* Action buttons */}
      <div style={{ padding: '12px 20px 12px', display: 'flex', gap: 8 }}>
        <button style={{
          flex: 1, padding: 14, background: 'transparent',
          border: `1px solid ${CC.ruleHi}`, color: CC.ink,
          fontFamily: CC.mono, fontSize: 10, letterSpacing: '0.2em',
          textTransform: 'uppercase', cursor: 'pointer',
        }}>Share</button>
        <button style={{
          flex: 1, padding: 14, background: 'transparent',
          border: `1px solid ${CC.ruleHi}`, color: CC.ink,
          fontFamily: CC.mono, fontSize: 10, letterSpacing: '0.2em',
          textTransform: 'uppercase', cursor: 'pointer',
        }}>Export .mp4</button>
        <button style={{
          flex: 1.3, padding: 14, background: CC.amber,
          border: 'none', color: CC.void,
          fontFamily: CC.mono, fontSize: 10, letterSpacing: '0.2em',
          textTransform: 'uppercase', cursor: 'pointer', fontWeight: 500,
        }}>Generate report</button>
      </div>

      <DashTabBar active="trips" />
    </div>
  );
}

Object.assign(window, { SettingsScreen, TripsScreen, IncidentScreen });

