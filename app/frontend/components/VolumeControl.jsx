import { useRef } from "react"
import { VolumeIcon, VolumeMuteIcon } from "./icons"

/**
 * The volume slider, shown only when the Web Playback SDK is driving playback
 * — it is the one engine that can actually set a level. The embed has no
 * volume method at all, so under it the player bar shows a note instead of a
 * control that could not do anything.
 *
 * Muting remembers where the knob was, so unmuting returns to that level
 * rather than to some default the listener never chose.
 */
export default function VolumeControl({ volume, onChange }) {
  const lastAudible = useRef(volume > 0 ? volume : 0.7)
  const muted = volume === 0

  if (!muted) lastAudible.current = volume

  const percent = Math.round(volume * 100)

  return (
    <div className="volume">
      <button
        type="button"
        className="volume__mute"
        onClick={() => onChange(muted ? lastAudible.current : 0)}
        aria-label={muted ? "Unmute" : "Mute"}
      >
        {muted ? <VolumeMuteIcon size={15} /> : <VolumeIcon size={15} />}
      </button>

      <input
        className="volume__range"
        type="range"
        min="0"
        max="100"
        step="1"
        value={percent}
        onChange={(event) => onChange(Number(event.target.value) / 100)}
        aria-label="Volume"
        aria-valuetext={`${percent}%`}
        style={{ "--progress": `${percent}%` }}
      />
    </div>
  )
}
