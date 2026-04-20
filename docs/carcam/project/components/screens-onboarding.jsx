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
