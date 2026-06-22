package lib

import (
	"bytes"
	"encoding/binary"
)

type Stream struct {
	Src           []byte
	Offset        int
	Length        int
	AllowOverflow bool
	LastUnread    int
	IsFinished    bool
}

func newStream(data []byte, allowOverflows bool) *Stream {
	return &Stream{
		Src:           data,
		Offset:        0,
		Length:        len(data),
		AllowOverflow: allowOverflows,
	}
}

func (s *Stream) Read(n int, shift bool) []byte {
	end := s.Offset + n
	if end > s.Length {
		if !s.AllowOverflow {
			panic("buffer overflow")
		}
		end = s.Length
	}

	chunk := s.Src[s.Offset:end]
	unread := n - len(chunk)
	s.LastUnread = unread

	if shift {
		s.Seek(n)
	}

	return chunk
}

func (s *Stream) ReadAsString(n int, shift bool) string {
	output := string(s.Read(n, shift))
	return output
}

func (s *Stream) Seek(n int) {
	s.Offset += n
	if s.Offset < 0 {
		s.Offset = 0
	}
	if s.Offset > s.Length {
		s.Offset = s.Length
	}
}

func (s *Stream) ReadNumber(order binary.ByteOrder, out any) interface{} {
	size := binary.Size(out)
	chunk := s.Read(size, true)
	buf := bytes.NewReader(chunk)
	binary.Read(buf, order, out)
	return out
}
