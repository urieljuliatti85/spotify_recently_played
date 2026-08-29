// Single-path glyphs on a 24×24 grid, sized by the `size` prop and coloured by
// `currentColor` so every icon inherits from whatever it sits in.
function Glyph({ size = 18, children, ...rest }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="currentColor"
      aria-hidden="true"
      focusable="false"
      {...rest}
    >
      {children}
    </svg>
  )
}

export const PlayIcon = (props) => (
  <Glyph {...props}>
    <path d="M8 5.5v13l11-6.5z" />
  </Glyph>
)

export const PauseIcon = (props) => (
  <Glyph {...props}>
    <path d="M7 5h3.5v14H7zm6.5 0H17v14h-3.5z" />
  </Glyph>
)

export const PrevIcon = (props) => (
  <Glyph {...props}>
    <path d="M7 5h2.2v14H7zm3.6 7L19 5.6v12.8z" />
  </Glyph>
)

export const NextIcon = (props) => (
  <Glyph {...props}>
    <path d="M14.8 5H17v14h-2.2zM5 5.6L13.4 12 5 18.4z" />
  </Glyph>
)

export const SearchIcon = (props) => (
  <Glyph {...props}>
    <path d="M10.5 3a7.5 7.5 0 015.96 12.08l4.23 4.23-1.38 1.38-4.23-4.23A7.5 7.5 0 1110.5 3zm0 2a5.5 5.5 0 100 11 5.5 5.5 0 000-11z" />
  </Glyph>
)

export const ShuffleIcon = (props) => (
  <Glyph {...props}>
    <path d="M17 3.5L21.5 8 17 12.5V9.5h-1.8l-2 3-1.2-1.8 2.3-3.2H17zM2.5 7h4l2.2 3.2-1.2 1.8-2-3h-3zM17 11.5L21.5 16 17 20.5V17.5h-2.7l-8-11.5H2.5v-2h4.9l8 11.5H17z" />
  </Glyph>
)

export const VolumeIcon = (props) => (
  <Glyph {...props}>
    <path d="M11 4v16l-5-4H3V8h3zm3.2 2.4a7 7 0 010 11.2l-1.2-1.6a5 5 0 000-8z" />
  </Glyph>
)

export const VolumeMuteIcon = (props) => (
  <Glyph {...props}>
    <path d="M11 4v16l-5-4H3V8h3zm3.3 4.1l1.4-1.4L18 9l2.3-2.3 1.4 1.4L19.4 10.4l2.3 2.3-1.4 1.4L18 11.8l-2.3 2.3-1.4-1.4 2.3-2.3z" />
  </Glyph>
)

export const CloseIcon = (props) => (
  <Glyph {...props}>
    <path d="M18.3 5.7L13.4 12l4.9 6.3-1.6 1.4L12 13.6l-4.7 6.1-1.6-1.4 4.9-6.3-4.9-6.3 1.6-1.4L12 10.4l4.7-6.1z" />
  </Glyph>
)

export const ChevronLeftIcon = (props) => (
  <Glyph {...props}>
    <path d="M15.4 4.6L8 12l7.4 7.4 1.4-1.4L10.8 12l6-6z" />
  </Glyph>
)

export const ChevronRightIcon = (props) => (
  <Glyph {...props}>
    <path d="M8.6 4.6L7.2 6l6 6-6 6 1.4 1.4L16 12z" />
  </Glyph>
)

export const NoteIcon = (props) => (
  <Glyph {...props}>
    <path d="M20 3v12.2a3.4 3.4 0 11-2-3.1V7.4l-8 1.9v8.9a3.4 3.4 0 11-2-3.1V6.6z" />
  </Glyph>
)

export const ClockIcon = (props) => (
  <Glyph {...props}>
    <path d="M12 2a10 10 0 110 20 10 10 0 010-20zm0 2a8 8 0 100 16 8 8 0 000-16zm1 3v4.6l3.2 1.9-1 1.7-4.2-2.5V7z" />
  </Glyph>
)

export const DiscIcon = (props) => (
  <Glyph {...props}>
    <path d="M12 2a10 10 0 110 20 10 10 0 010-20zm0 2a8 8 0 100 16 8 8 0 000-16zm0 5.5a2.5 2.5 0 110 5 2.5 2.5 0 010-5z" />
  </Glyph>
)

export const ExternalIcon = (props) => (
  <Glyph {...props}>
    <path d="M14 3h7v7h-2V6.4l-8.3 8.3-1.4-1.4L17.6 5H14zM5 5h5v2H7v10h10v-3h2v5H5z" />
  </Glyph>
)

export const YoutubeIcon = (props) => (
  <Glyph {...props}>
    <path
      fillRule="evenodd"
      clipRule="evenodd"
      d="M2 8a4 4 0 014-4h12a4 4 0 014 4v8a4 4 0 01-4 4H6a4 4 0 01-4-4zm8 1.6v4.8l4.5-2.4z"
    />
  </Glyph>
)
