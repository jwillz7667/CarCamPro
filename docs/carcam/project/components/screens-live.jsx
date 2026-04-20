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
