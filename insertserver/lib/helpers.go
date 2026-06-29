package lib

import (
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"math"
	"strings"
	"unicode/utf8"
)

func matrixFromOrientId(i uint8) [9]float32 {
	i -= 1
	m := [9]float32{}
	if i >= 35 || (i/6)%3 == i%3 {
		return m
	}
	m[(i/6)%3*3] = 1.0 - float32((i/18)*2)
	m[(i%6)%3*3+1] = 1.0 - float32((i%6)/3*2)
	// Set Z axis to cross product of X and Y.
	m[2] = m[3]*m[7] - m[4]*m[6]
	m[5] = m[6]*m[1] - m[7]*m[0]
	m[8] = m[0]*m[4] - m[1]*m[3]
	m[2] = m[3]*m[7] - m[4]*m[6]
	m[5] = m[6]*m[1] - m[7]*m[0]
	m[8] = m[0]*m[4] - m[1]*m[3]
	return m
}
func fixBase64Padding(s string) string {
	missing := len(s) % 4
	if missing != 0 {
		s += strings.Repeat("=", 4-missing)
	}
	return s
}

func DecodeProp(data *Stream, typeId byte, sizeof int, rbxm *RBXM) ([]Property, error) {
	properties := make([]Property, sizeof)
	switch typeId {
	case 0x01:
		//string
		for i := 0; i < sizeof; i++ {
			out := RbxString(data)
			encoded := false
			//isFilteredString := false
			raw := []byte(out)
			if !utf8.Valid(raw) {
				encoded = true
				out = base64.StdEncoding.EncodeToString(raw)
			} else {

			}
			properties[i] = Property{
				Type:    "string",
				Value:   out,
				Encoded: encoded,
			}
		}
	case 0x02:
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type:  "boolean",
				Value: data.ReadAsString(1, true) != "\x00",
			}
		}
	case 0x03:
		for i, v := range Int32Array(data, sizeof) {
			properties[i] = Property{
				Type:  "int32",
				Value: v,
			}
		}
	case 0x04:
		for i, v := range RbxF32Array(data, sizeof) {
			properties[i] = Property{
				Type:  "rbxf32",
				Value: v,
			}
		}
	case 0x05:
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type:  "float64",
				Value: PurifyFloatValue(Float64(data)),
			}
		}
	case 0x06:
		scale := RbxF32Array(data, sizeof)
		offset := Int32Array(data, sizeof)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type: "udim",
				Value: UDim{
					Scale:  scale[i],
					Offset: offset[i],
				},
			}
		}
	case 0x07:
		scaleX, scaleY := RbxF32Array(data, sizeof), RbxF32Array(data, sizeof)
		offsetX, offsetY := Int32Array(data, sizeof), Int32Array(data, sizeof)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type: "udim2",
				Value: UDim2{
					X: UDim{
						Scale:  scaleX[i],
						Offset: offsetX[i],
					},
					Y: UDim{
						Scale:  scaleY[i],
						Offset: offsetY[i],
					},
				},
			}
		}
	case 0x08:
		for i := 0; i < sizeof; i++ {
			var values [6]float32
			data.ReadNumber(binary.LittleEndian, &values)
			properties[i] = Property{
				Type: "ray",
				Value: Ray{
					Origin:    []float32{PurifyFloat32Value(values[0]), PurifyFloat32Value(values[1]), PurifyFloat32Value(values[2])},
					Direction: []float32{PurifyFloat32Value(values[3]), PurifyFloat32Value(values[4]), PurifyFloat32Value(values[5])},
				},
			}
		}
	case 0x0B:
		for i, v := range unsignedIntArray(data, sizeof, binary.BigEndian) {
			properties[i] = Property{
				Type:  "brickcolor",
				Value: v,
			}
		}
	case 0x0C:
		r := RbxF32Array(data, sizeof)
		g := RbxF32Array(data, sizeof)
		b := RbxF32Array(data, sizeof)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type:  "color3",
				Value: []float32{r[i], g[i], b[i]},
			}
		}
	case 0x0D:
		x := RbxF32Array(data, sizeof)
		y := RbxF32Array(data, sizeof)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type:  "vector2",
				Value: []float32{x[i], y[i]},
			}
		}
	case 0x0E:
		x := RbxF32Array(data, sizeof)
		y := RbxF32Array(data, sizeof)
		z := RbxF32Array(data, sizeof)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type:  "vector3",
				Value: []float32{x[i], y[i], z[i]},
			}
		}
	case 0x10:
		matrices := make([][9]float32, sizeof)
		for i := 0; i < sizeof; i++ {
			var rawOrientation uint8
			data.ReadNumber(binary.LittleEndian, &rawOrientation)
			if rawOrientation > 0 {
				values := matrixFromOrientId(rawOrientation)
				matrices[i] = values
			} else {
				var values [9]float32
				data.ReadNumber(binary.LittleEndian, &values)
				matrices[i] = values
			}
		}
		cfX := RbxF32Array(data, sizeof)
		cfY := RbxF32Array(data, sizeof)
		cfZ := RbxF32Array(data, sizeof)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type: "cframe",
				Value: map[string]any{
					"position": map[string]any{"vector3": []float32{cfX[i], cfY[i], cfZ[i]}},
					"rotation": matrices[i],
				},
			}
		}
	case 0x11:
		quaternions := make([]Quaternion, sizeof)
		for i := 0; i < sizeof; i++ {
			var values [4]float32
			data.ReadNumber(binary.LittleEndian, &values)
			quaternions[i] = Quaternion{
				X: values[0],
				Y: values[1],
				Z: values[2],
				W: values[3],
			}
		}
		cfX := RbxF32Array(data, sizeof)
		cfY := RbxF32Array(data, sizeof)
		cfZ := RbxF32Array(data, sizeof)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type:  "qcframe",
				Value: []float32{cfX[i], cfY[i], cfZ[i], quaternions[i].X, quaternions[i].Y, quaternions[i].Z, quaternions[i].W},
			}
		}
	case 0x12:
		for i, v := range unsignedIntArray(data, sizeof, binary.BigEndian) {
			properties[i] = Property{
				Type:  "enum",
				Value: v,
			}
		}
	case 0x13:
		for i, v := range RefArray(data, sizeof) {
			properties[i] = Property{
				Type:  "ref",
				Value: v,
			}
		}
	case 0x14:
		for i := 0; i < sizeof; i++ {
			var values [3]int16
			data.ReadNumber(binary.LittleEndian, &values)
			properties[i] = Property{
				Type:  "vector3int16",
				Value: values,
			}
		}
	case 0x15:
		for i := 0; i < sizeof; i++ {
			var kpCount uint32
			data.ReadNumber(binary.LittleEndian, &kpCount)
			keypoints := make([]any, kpCount)
			for k := 0; k < int(kpCount); k++ {
				var vals [3]float32
				data.ReadNumber(binary.LittleEndian, &vals)
				keypoints[k] = map[string]any{
					"nskp": vals,
				}
			}
			properties[i] = Property{
				Type:  "numbersequence",
				Value: keypoints,
			}
		}
	case 0x16:
		for i := 0; i < sizeof; i++ {
			var kpCount uint32
			data.ReadNumber(binary.LittleEndian, &kpCount)
			keypoints := make([]any, kpCount)
			for k := 0; k < int(kpCount); k++ {
				var tVal float32
				var color3Vals [3]float32
				data.ReadNumber(binary.LittleEndian, &tVal)
				data.ReadNumber(binary.LittleEndian, &color3Vals)
				keypoints[k] = map[string]any{
					"cskp": map[string]any{
						"t":      tVal,
						"color3": color3Vals,
					},
				}
				data.ReadNumber(binary.LittleEndian, &[1]float32{}) //envolpe (not used for some reason)
			}
			properties[i] = Property{
				Type:  "colorsequence",
				Value: keypoints,
			}
		}
	case 0x17:
		for i := 0; i < sizeof; i++ {
			var values [2]float32
			data.ReadNumber(binary.LittleEndian, &values)
			properties[i] = Property{
				Type:  "numberrange",
				Value: values,
			}
		}
	case 0x18:
		xmn, ymn := RbxF32Array(data, sizeof), RbxF32Array(data, sizeof)
		xmx, ymx := RbxF32Array(data, sizeof), RbxF32Array(data, sizeof)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type: "rect",
				Value: Rect{
					Position1: []float32{xmn[i], ymn[i]},
					Position2: []float32{xmx[i], ymx[i]},
				},
			}
		}
	case 0x19:
		for i := 0; i < sizeof; i++ {
			var bitFlag uint8
			data.ReadNumber(binary.LittleEndian, &bitFlag)
			if bitFlag == 0 || bitFlag == 2 {
				properties[i] = Property{
					Type:  "physprops",
					Value: nil,
				}
				continue
			}
			var values [5]float32
			data.ReadNumber(binary.LittleEndian, &values)
			var absorption float32 = 1.0 //default
			if bitFlag == 3 {
				data.ReadNumber(binary.LittleEndian, &absorption)
			}
			properties[i] = Property{
				Type:  "physprops",
				Value: []float32{PurifyFloat32Value(values[0]), PurifyFloat32Value(values[1]), PurifyFloat32Value(values[2]), PurifyFloat32Value(values[3]), PurifyFloat32Value(values[4]), PurifyFloat32Value(absorption)},
			}
		}
	case 0x1A:
		r := data.Read(sizeof, true)
		g := data.Read(sizeof, true)
		b := data.Read(sizeof, true)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type:  "rgbc3",
				Value: []int{int(r[i]), int(g[i]), int(b[i])},
			}
		}
	case 0x1B:
		for i, v := range Int64Array(data, sizeof) {
			properties[i] = Property{
				Type:  "int64",
				Value: v,
			}
		}
	case 0x1C:
		strings := unsignedIntArray(data, sizeof, binary.BigEndian)
		for i := 0; i < sizeof; i++ {
			properties[i] = Property{
				Type:  "sharedstr",
				Value: rbxm.SharedStrings[strings[i]],
			}
		}
	case 0x20:
		for i := 0; i < sizeof; i++ {
			family := RbxString(data)
			var weight int16
			data.ReadNumber(binary.LittleEndian, &weight)
			var style uint8
			data.ReadNumber(binary.LittleEndian, &style)
			RbxString(data) //cachedFaceId
			properties[i] = Property{
				Type: "font",
				Value: Font{
					FontFamily: family,
					FontWeight: int(weight),
					FontStyle:  int(style),
				},
			}
		}
	case 0x22:
		sourceTypeInts := unsignedIntArray(data, sizeof, binary.BigEndian)
		sourceTypes := []string{}
		for _, st := range sourceTypeInts {
			switch st {
			case 0:
				sourceTypes = append(sourceTypes, "nul")
			case 1:
				sourceTypes = append(sourceTypes, "uri")
			case 2:
				sourceTypes = append(sourceTypes, "obj")
			}
		}
		var UriCount uint32
		var Uris []string
		data.ReadNumber(binary.LittleEndian, &UriCount)
		for i := 0; i < int(UriCount); i++ {
			Uris = append(Uris, RbxString(data))
		}
		var ObjCount uint32
		data.ReadNumber(binary.LittleEndian, &ObjCount)
		Objs := RefArray(data, int(ObjCount))
		var ExtObjCount uint32
		data.ReadNumber(binary.LittleEndian, &ExtObjCount)
		RefArray(data, int(ExtObjCount)) //external refs, not applicable
		uriIndex := 0
		objIndex := 0
		for i := 0; i < sizeof; i++ {
			t := sourceTypes[i]
			var propVal any
			switch t {
			case "uri":
				propVal = Uris[uriIndex]
				uriIndex += 1
			case "obj":
				propVal = Objs[objIndex]
				objIndex += 1
			}
			properties[i] = Property{
				Type:  "content",
				Value: propVal,
				Ctype: t,
			}
		}
	}
	return properties, nil
}

func ParseTagsValue(_prop Property) []string {
	refVal := _prop.Value.(string)
	if len(refVal) > 0 {
		if _prop.Encoded {
			val, err := base64.StdEncoding.DecodeString(refVal)
			if err != nil {
				fmt.Printf("Failed to deserialize tags! %v\n", err.Error())
				return []string{}
			}
			refVal = string(val)
		}
		tagsArray := strings.Split(refVal, "\x00")
		return tagsArray
	}
	return []string{}
}

func ParseAttributesValue(_prop Property) map[string]Attribute {
	refVal := fmt.Sprintf("%v", _prop.Value)
	retVal := map[string]Attribute{}
	if len(refVal) > 0 {
		if _prop.Encoded {
			val, err := base64.StdEncoding.DecodeString(refVal)
			if err != nil {
				fmt.Printf("Failed to deserialize attributes! %v\n", err.Error())
				return retVal
			}
			refVal = string(val)
		}
		data := newStream([]byte(refVal), false)
		var length uint32
		data.ReadNumber(binary.LittleEndian, &length)
		for i := 0; i < int(length); i++ {
			attr := RbxString(data)
			var typeId uint8
			data.ReadNumber(binary.LittleEndian, &typeId)
			switch typeId {
			case 2:
				retVal[attr] = Attribute{
					Type:  "string",
					Value: RbxString(data),
				}
			case 3:
				retVal[attr] = Attribute{
					Type:  "boolean",
					Value: data.ReadAsString(1, true) != "\x00",
				}
			case 5:
				var f32 float32
				data.ReadNumber(binary.LittleEndian, &f32)
				retVal[attr] = Attribute{
					Type:  "f32",
					Value: PurifyFloat32Value(f32),
				}
			case 6:
				var f64 float64
				data.ReadNumber(binary.LittleEndian, &f64)
				retVal[attr] = Attribute{
					Type:  "f64",
					Value: PurifyFloatValue(f64),
				}
			case 9:
				var s float32
				var o int32
				data.ReadNumber(binary.LittleEndian, &s)
				data.ReadNumber(binary.LittleEndian, &o)
				retVal[attr] = Attribute{
					Type: "udim",
					Value: UDim{
						Scale:  s,
						Offset: int(o),
					},
				}
			case 10:
				var sx float32
				var ox int32
				var sy float32
				var oy int32
				data.ReadNumber(binary.LittleEndian, &sx)
				data.ReadNumber(binary.LittleEndian, &ox)
				data.ReadNumber(binary.LittleEndian, &sy)
				data.ReadNumber(binary.LittleEndian, &oy)
				retVal[attr] = Attribute{
					Type: "udim",
					Value: UDim2{
						X: UDim{
							Scale:  sx,
							Offset: int(ox),
						},
						Y: UDim{
							Scale:  sy,
							Offset: int(oy),
						},
					},
				}
			case 14:
				var u32 uint32
				data.ReadNumber(binary.LittleEndian, &u32)
				retVal[attr] = Attribute{
					Type:  "brickcolor",
					Value: u32,
				}
			case 15:
				var vals [3]float32
				data.ReadNumber(binary.LittleEndian, &vals)
				retVal[attr] = Attribute{
					Type:  "color3",
					Value: vals,
				}
			case 16:
				var vals [2]float32
				data.ReadNumber(binary.LittleEndian, &vals)
				retVal[attr] = Attribute{
					Type:  "vector2",
					Value: vals,
				}
			case 17:
				var vals [3]float32
				data.ReadNumber(binary.LittleEndian, &vals)
				retVal[attr] = Attribute{
					Type:  "vector3",
					Value: vals,
				}
			case 20:
				var vals [3]float32
				data.ReadNumber(binary.LittleEndian, &vals)
				var rawOrientation uint8
				data.ReadNumber(binary.LittleEndian, &rawOrientation)
				var matrix [9]float32
				if rawOrientation > 0 {
					matrix = matrixFromOrientId(rawOrientation)
				} else {
					var values [9]float32
					data.ReadNumber(binary.LittleEndian, &values)
					matrix = values
				}
				retVal[attr] = Attribute{
					Type: "cframe",
					Value: map[string]any{
						"position": map[string]any{"vector3": vals},
						"rotation": matrix,
					},
				}
			case 23:
				var kpCount uint32
				data.ReadNumber(binary.LittleEndian, &kpCount)
				keypoints := make([]any, kpCount)
				for k := 0; k < int(kpCount); k++ {
					var vals [3]float32
					data.ReadNumber(binary.LittleEndian, &vals)
					keypoints[k] = map[string]any{
						"nskp": [3]float32{vals[2], vals[0], vals[1]},
					}
				}
			case 25:
				var kpCount uint32
				data.ReadNumber(binary.LittleEndian, &kpCount)
				keypoints := make([]any, kpCount)
				for k := 0; k < int(kpCount); k++ {
					var eVal float32
					var tVal float32
					var color3Vals [3]float32
					data.ReadNumber(binary.LittleEndian, &eVal)
					data.ReadNumber(binary.LittleEndian, &tVal)
					data.ReadNumber(binary.LittleEndian, &color3Vals)
					keypoints[k] = map[string]any{
						"cskp": map[string]any{
							"t":      tVal,
							"color3": color3Vals,
						},
					}
				}
			case 27:
				var vals [2]float32
				data.ReadNumber(binary.LittleEndian, &vals)
				retVal[attr] = Attribute{
					Type:  "numberrange",
					Value: vals,
				}
			case 28:
				var vals1 [2]float32
				var vals2 [2]float32
				data.ReadNumber(binary.LittleEndian, &vals1)
				data.ReadNumber(binary.LittleEndian, &vals2)
				retVal[attr] = Attribute{
					Type: "rect",
					Value: Rect{
						Position1: vals1[:],
						Position2: vals2[:],
					},
				}
			}
		}
	}
	return retVal
}

func PurifyFloat32Value(Val float32) float32 {
	ReturnVal := Val
	FloatVal := float32(Val)
	if math.IsInf(float64(FloatVal), 0) {
		ReturnVal = 1000000000000
	} else if math.IsInf(float64(FloatVal), -1) {
		ReturnVal = -1000000000000
	} else if math.IsNaN(float64(FloatVal)) {
		ReturnVal = 0
	}
	return ReturnVal
}
func PurifyFloatValue(Val float64) float64 {
	ReturnVal := Val
	FloatVal := float64(Val)
	if math.IsInf(FloatVal, 0) {
		ReturnVal = 1000000000000
	} else if math.IsInf(FloatVal, -1) {
		ReturnVal = -1000000000000
	} else if math.IsNaN(FloatVal) {
		ReturnVal = 0
	}
	return ReturnVal
}
