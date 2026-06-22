/*
RBXM Parser Library
*/
package lib

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"strconv"

	"github.com/klauspost/compress/zstd"
	"github.com/pierrec/lz4/v4"
)

const RBXFILE_HEADER string = "<roblox"
const BIN_FLAG string = "!"
const RBXM_SIG string = "\x89\xff\x0d\x0a\x1a\x0a"
const ZLIB_HEADER string = "\x28\xb5\x2f\xfd"
const xmlprefixthing string = "<?xml version='1.0' encoding='utf-8'?>"
const xmlprefixthing2 string = "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
const maxFileSizeMiB int = 20 //max file size (avoids memory overflow)

var validChunkIdents []string = []string{
	"END\x00",
	"INST",
	"META",
	"PRNT",
	"PROP",
	"SIGN",
	"SSTR",
}

/*
CHUNK_MODULES={
    "INST":chunks.INST,
    "META":chunks.META,
    "PRNT":chunks.PRNT,
    "PROP":chunks.PROP,
    "SSTR":chunks.SSTR
    #SIGN and END\0 are not processed because they dont contain usable data
};
*/
/*
Processes RBXM Chunk Data

    Parameters:
        chunkStore - Dictionary to store Chunk values
        ident - Chunk Identifier
*/
type ChunkHandler func(data *Stream, rbxm *RBXM) error

var CHUNK_MODULES = map[string]ChunkHandler{
	"INST": INST,
	"META": META,
	"PRNT": PRNT,
	"PROP": PROP,
	"SSTR": SSTR,
}

func ProcessChunk(chunkStore map[string][]Chunk, ident string, rbxm *RBXM) error {
	chunks := chunkStore[ident]
	for _, chunk := range chunks {
		if handler, ok := CHUNK_MODULES[chunk.Header]; ok {
			err := handler(newStream(chunk.Data, false), rbxm)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

/* Decompresses any RBXM Chunk */
func InitChunk(content *Stream, index int) (Chunk, error) {
	chunk := Chunk{
		InternalId:       index,
		Header:           content.ReadAsString(4, true),
		DecompressedSize: 0,
		CompressedSize:   0,
	}
	content.ReadNumber(binary.LittleEndian, &(chunk.CompressedSize))
	content.ReadNumber(binary.LittleEndian, &(chunk.DecompressedSize))
	if content.ReadAsString(4, true) != "\x00\x00\x00\x00" {
		return chunk, errors.New("Invalid Chunk Header on chunk index " + strconv.FormatInt(int64(index), 10))
	}
	if chunk.CompressedSize == 0 {
		chunk.Data = content.Read(int(chunk.DecompressedSize), true)
	} else {
		chunkData := content.Read(int(chunk.CompressedSize), true)
		if len(chunkData) >= 4 &&
			chunkData[0] == 0x28 && chunkData[1] == 0xB5 &&
			chunkData[2] == 0x2F && chunkData[3] == 0xFD {
			//zstd
			dec, _ := zstd.NewReader(nil)
			data, err := dec.DecodeAll(chunkData, nil)
			if err != nil {
				return chunk, errors.New("Decompression failed on chunk index " + strconv.FormatInt(int64(index), 10))
			}
			chunk.Data = data
		} else {
			dest := make([]byte, int(chunk.DecompressedSize))
			n, err := lz4.UncompressBlock(chunkData, dest)
			if err != nil {
				return chunk, errors.New("Decompression failed on chunk index " + strconv.FormatInt(int64(index), 10))
			}
			chunk.Data = dest[:n]
		}
	}
	return chunk, nil
}

/*
Reads an RBXM/RBXMX stream and returns its structured representation.

	Parameters:
	    data  - Raw RBXM/RBXMX XML content.

	Returns:
	    RBXM  - Parsed model tree.
	    error - Non-nil if the stream is malformed or unsupported.
*/
func Parse(data string) (*RBXM, error) {
	if len(data) > (maxFileSizeMiB * 1024 * 1024) {
		return nil, fmt.Errorf("File size is too large (exceeds %d MiB), please load a smaller file", maxFileSizeMiB)
	}
	rawData := newStream([]byte(data), false)
	if rawData.ReadAsString(len(xmlprefixthing), false) == xmlprefixthing || rawData.ReadAsString(len(xmlprefixthing2), false) == xmlprefixthing2 {
		fmt.Println("Detected RBXMX file, switching to RBXMX parser...")
		return ParseXML(data)
	}
	if rawData.ReadAsString(len(RBXFILE_HEADER), true) != RBXFILE_HEADER {
		return nil, errors.New("Failed to parse file, it is not a valid RBXM/RBXMX file.")
	}
	if rawData.ReadAsString(1, true) != BIN_FLAG {
		fmt.Println("Detected RBXMX file, switching to RBXMX parser...")
		return ParseXML(data)
	}
	if rawData.ReadAsString(6, true) != RBXM_SIG {
		return nil, errors.New("Failed to parse file, it is not a valid RBXM file.")
	}
	if rawData.ReadAsString(2, true) != "\x00\x00" {
		return nil, errors.New("File version is not supported. Only version 0 is supported. IF YOU SEE THIS MESSAGE, CONTACT THE DEVELOPER, IT MEANS RBXM HAS CHANGED VERSIONS.")
	}
	var counts [2]uint32
	rawData.ReadNumber(binary.LittleEndian, &counts)
	rbxm := RBXM{
		Metadata:      map[string]any{},
		SharedStrings: []string{},
		ClassCount:    0,
		InstanceCount: 0,
		ClassRef:      make([]ClassRefEntry, counts[0]),
		InstRef:       make([]*Instance, counts[1]),
		Tree:          []*Instance{},
	}
	rbxm.ClassCount = counts[0]
	rbxm.InstanceCount = counts[1]
	chunkStore := map[string][]Chunk{}
	for i := 0; i < len(validChunkIdents); i++ {
		chunkStore[validChunkIdents[i]] = []Chunk{}
	}
	if rawData.ReadAsString(8, true) != "\x00\x00\x00\x00\x00\x00\x00\x00" {
		return &rbxm, errors.New("Failed to parse file, it is not a valid RBXM file.")
	}
	// its chunk time
	chunkIndex := 0
	hasReachedEndChunk := false
	for !hasReachedEndChunk {
		chunk, err := InitChunk(rawData, chunkIndex)
		if err != nil {
			return &rbxm, err
		}
		ident := chunk.Header
		if ident == "END\x00" {
			hasReachedEndChunk = true
			break
		}
		if _, ok := chunkStore[ident]; ok {
			chunkStore[ident] = append(chunkStore[ident], chunk)
		} else {
			return &rbxm, errors.New("Unknown Chunk Identifier on chunk index: " + strconv.FormatInt(int64(chunkIndex), 10))
		}
		chunkIndex++
	}
	ProcessChunk(chunkStore, "META", &rbxm)
	ProcessChunk(chunkStore, "SSTR", &rbxm)
	ProcessChunk(chunkStore, "INST", &rbxm)
	ProcessChunk(chunkStore, "PROP", &rbxm)
	ProcessChunk(chunkStore, "PRNT", &rbxm)
	return &rbxm, nil
}

/*
Reads an RBXM/RBXMX file and returns its structured representation.

	Parameters:
	    path  - Path to RBXM/RBXMX file

	Returns:
	    RBXM  - Parsed model tree.
	    error - Non-nil if the stream is malformed or unsupported.
*/
func ParseFile(path string) (*RBXM, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("%s", "Failed to read file: "+err.Error())
	}
	return Parse(string(content))
}
