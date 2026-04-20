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
