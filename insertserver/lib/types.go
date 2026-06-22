package lib

import (
	"encoding/binary"
	"math"
)

type UDim struct {
	Scale  float32 `json:"scale"`
	Offset int     `json:"offset"`
}
type UDim2 struct {
	X UDim `json:"x"`
	Y UDim `json:"y"`
}
type Font struct {
	FontFamily string `json:"fontFamily"`
	FontWeight int    `json:"fontWeight"`
	FontStyle  int    `json:"fontStyle"`
}
type Rect struct {
	Position1 []float32 `json:"pos1"`
	Position2 []float32 `json:"pos2"`
}
type Ray struct {
	Origin    []float32 `json:"origin"`
	Direction []float32 `json:"direction"`
}
type NumberSequenceKeypoint struct {
	Keypoint []float32 `json:"nskp"`
}
type Quaternion struct {
	X float32 `json:"x"`
	Y float32 `json:"y"`
	Z float32 `json:"z"`
	W float32 `json:"w"`
}
type Property struct {
	Type    string `json:"type"`
	Value   any    `json:"value"`
	Encoded bool   `json:"enc,omitempty"`
	Ctype   string `json:"ctyp,omitempty"`
}
type Attribute struct {
	Type  string `json:"type"`
	Value any    `json:"value"`
}
type Chunk struct {
	InternalId       int
	Header           string
	Data             []byte
	CompressedSize   uint32
	DecompressedSize uint32
}
type Instance struct {
	Attributes map[string]Attribute `json:"attributes"`
	ClassId    int                  `json:"ClassId"`
	ClassName  string               `json:"ClassName"`
	Ref        int                  `json:"Ref"`
	Properties map[string]Property  `json:"properties"`
	Tags       []string             `json:"tags"`
	Children   []*Instance          `json:"children"`
}
type ClassRefEntry struct {
	Name   string `json:"Name"`
	Refs   []int  `json:"Refs"`
	Sizeof int    `json:"Sizeof"`
}
type RBXM struct {
	Metadata      map[string]any  `json:"metadata"`
	SharedStrings []string        `json:"shared_strings"`
	StringHashes  []string        `json:"string_hashes,omitempty"`
	ClassCount    uint32          `json:"class_count"`
	InstanceCount uint32          `json:"instance_count"`
	ClassRef      []ClassRefEntry `json:"class_ref"`
	InstRef       []*Instance     `json:"inst_ref"`
	Tree          []*Instance     `json:"tree"`
}

func transformInt(x int) int {
	return (x >> 1) ^ -(x & 1)
}
func rbxF32(x uint32) float32 {
	//x = ((x >> 1) | ((x & 1) << 31)) & 0xFFFFFFFF
	return math.Float32frombits((x >> 1) | (x << 31))
}
func RbxString(data *Stream) string {
	var length uint32
	data.ReadNumber(binary.LittleEndian, &length)
	return string(data.Read(int(length), true))
}
func Int32(data *Stream) int {
	var readFromFile uint32
	data.ReadNumber(binary.BigEndian, &readFromFile)
	return transformInt(int(readFromFile))
}
func Int64(data *Stream) int {
	var readFromFile uint64
	data.ReadNumber(binary.BigEndian, &readFromFile)
	return transformInt(int(readFromFile))
}
func Float32(data *Stream) float32 {
	var readFromFile uint32
	data.ReadNumber(binary.BigEndian, &readFromFile)
	return PurifyFloat32Value(rbxF32(readFromFile))
}
func Float64(data *Stream) float64 {
	var readFromFile float64
	data.ReadNumber(binary.LittleEndian, &readFromFile)
	return readFromFile
}

func InterleaveArrayWithSize(data *Stream, count int, sizeof int) *Stream {
	if count < 0 {
		return newStream([]byte{0}, false)
	}
	raw := data.Read(count*sizeof, true)
	out := make([]byte, 0, count*sizeof)
	for i := 0; i < count; i++ {
		for s := 0; s < sizeof; s++ {
			out = append(out, raw[i+count*s])
		}
	}
	return newStream(out, false)
}

func unsignedIntArray(data *Stream, count int, endian binary.ByteOrder) []uint32 {
	if count < 1 {
		return []uint32{}
	}
	strings := InterleaveArrayWithSize(data, count, 4)
	values := make([]uint32, count)
	strings.ReadNumber(endian, &values)
	return values
}
func Int32Array(data *Stream, count int) []int {
	if count < 1 {
		return []int{}
	}
	strings := InterleaveArrayWithSize(data, count, 4)
	values := make([]int, count)
	for i := 0; i < count; i++ {
		var readFromFile uint32
		strings.ReadNumber(binary.BigEndian, &readFromFile)
		values[i] = transformInt(int(readFromFile))
	}
	return values
}
func Int64Array(data *Stream, count int) []int {
	if count < 1 {
		return []int{}
	}
	strings := InterleaveArrayWithSize(data, count, 8)
	values := make([]int, count)
	for i := 0; i < count; i++ {
		var readFromFile uint64
		strings.ReadNumber(binary.BigEndian, &readFromFile)
		values[i] = transformInt(int(readFromFile))
	}
	return values
}
func RbxF32Array(data *Stream, count int) []float32 {
	if count < 1 {
		return []float32{}
	}
	strings := InterleaveArrayWithSize(data, count, 4)
	values := make([]float32, count)
	for i := 0; i < count; i++ {
		var readFromFile uint32
		strings.ReadNumber(binary.BigEndian, &readFromFile)
		values[i] = PurifyFloat32Value(rbxF32(readFromFile))
	}
	return values
}
func RefArray(data *Stream, count int) []int {
	if count < 1 {
		return []int{}
	}
	out := make([]int, count)
	refs := Int32Array(data, count)
	last := 0
	for i := 0; i < count; i++ {
		ref := last + refs[i]
		out[i] = ref
		last = ref
	}
	return out
}
