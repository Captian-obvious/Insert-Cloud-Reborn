package lib

import (
	"encoding/xml"
	"fmt"
	"strconv"
	"strings"
)

type XMLRoot struct {
	XMLName       xml.Name        `xml:"roblox"`
	Meta          []XMLMeta       `xml:"Meta"`
	SharedStrings []XMLSharedRoot `xml:"SharedStrings"`
	Items         []XMLItem       `xml:"Item"`
}

type XMLMeta struct {
	Name  string `xml:"name,attr"`
	Value string `xml:",chardata"`
}

type XMLSharedRoot struct {
	Strings []XMLSharedString `xml:"SharedString"`
}

type XMLSharedString struct {
	MD5   string `xml:"md5,attr"`
	Value string `xml:",chardata"`
}

type XMLItem struct {
	Class      string        `xml:"class,attr"`
	Referent   string        `xml:"referent,attr"`
	Properties XMLProperties `xml:"Properties"`
	Children   []*XMLItem    `xml:"Item"`
}

type XMLProperties struct {
	List []*XMLProperty `xml:",any"`
}

type XMLProperty struct {
	XMLName  xml.Name
	Name     string        `xml:"name,attr"`
	Value    string        `xml:",chardata"`
	Attrs    []xml.Attr    `xml:",any,attr"`
	Children []XMLProperty `xml:",any"`
}

type RbxmxContext struct {
	ClassRefMap    map[string]*XMLClassRefEntry
	RefMap         []string
	CurrentRef     int
	CurrentClassId int
	SharedStrings  []string
	SharedHashes   []string
}

type XMLClassRefEntry struct {
	Name      string
	Referents []int
	ClassId   int
}

func newContext() *RbxmxContext {
	return &RbxmxContext{
		ClassRefMap: make(map[string]*XMLClassRefEntry),
		RefMap:      []string{},
	}
}

func (r *RbxmxContext) addClassRef(class string, ref int) {
	if _, exists := r.ClassRefMap[class]; exists {
		r.ClassRefMap[class].Referents = append(r.ClassRefMap[class].Referents, ref)
	} else {
		r.ClassRefMap[class] = &XMLClassRefEntry{
			Name:      class,
			Referents: []int{ref},
			ClassId:   r.CurrentClassId,
		}
		r.CurrentClassId += 1
	}
}

func (r *RbxmxContext) addReferent(ref string) {
	r.RefMap = append(r.RefMap, ref)
}

func (r *RbxmxContext) getSharedString(hash string) int {
	for index, shhash := range r.SharedHashes {
		if hash == shhash {
			return index
		}
	}
	return 0
}

func (r *RbxmxContext) getCurrentRef() int {
	return r.CurrentRef
}

func (r *RbxmxContext) getRefFromReferent(referent string) int {
	for ref, v := range r.RefMap {
		if v == referent {
			return ref
		}
	}

	return -1
}

func (r *RbxmxContext) getClassRefById(classId int) *XMLClassRefEntry {
	for _, refs := range r.ClassRefMap {
		if refs.ClassId == classId {
			return refs
		}
	}
	return nil
}

func (r *RbxmxContext) getCurrentClassId() int {
	return r.CurrentClassId - 1
}

func (r *RbxmxContext) incCurrentRef() int {
	r.CurrentRef += 1
	return r.CurrentRef - 1
}

/*
Reads an RBXMX stream and returns its structured representation.

	Parameters:
	    data  - Raw RBXMX XML content.

	Returns:
	    RBXM  - Parsed model tree.
	    error - Non-nil if the stream is malformed or unsupported.
*/
func ParseXML(data string) (*RBXM, error) {
	var doc XMLRoot
	if err := xml.Unmarshal([]byte(data), &doc); err != nil {
		return nil, err
	}

	rbxm := RBXM{
		Metadata:      map[string]any{},
		SharedStrings: []string{},
		StringHashes:  []string{},
		ClassCount:    0,
		InstanceCount: 0,
		ClassRef:      []ClassRefEntry{},
		InstRef:       []*Instance{},
		Tree:          []*Instance{},
	}
	for _, item := range doc.Meta {
		key := item.Name
		value := item.Value
		if key == "ExplicitAutoJoints" {
			rbxm.Metadata[key] = bool_from_string(value)
		} else {
			rbxm.Metadata[key] = value
		}
	}
	for _, ssRoot := range doc.SharedStrings {
		for _, string_elem := range ssRoot.Strings {
			rbxm.SharedStrings = append(rbxm.SharedStrings, string_elem.Value)
			rbxm.StringHashes = append(rbxm.StringHashes, string_elem.MD5)
		}
	}
	ctx := newContext()
	ctx.SharedHashes = rbxm.StringHashes
	ctx.SharedStrings = rbxm.SharedStrings
	for _, item := range doc.Items {
		rbxm.Tree = append(rbxm.Tree, buildTree(ctx, &item))
	}
	rbxm.ClassCount = uint32(len(ctx.ClassRefMap))
	rbxm.ClassRef = make([]ClassRefEntry, rbxm.ClassCount)
	for i := 0; i < int(rbxm.ClassCount); i++ {
		classrefent := ctx.getClassRefById(i)
		if classrefent != nil {
			rbxm.ClassRef[i] = ClassRefEntry{
				Name:   classrefent.Name,
				Refs:   classrefent.Referents,
				Sizeof: len(classrefent.Referents),
			}
		}
	}
	rbxm.InstanceCount = uint32(len(ctx.RefMap))
	return &rbxm, nil
}

/*
Recursively builds and applies properties to the XML Tree
*/
func buildTree(ctx *RbxmxContext, elem *XMLItem) *Instance {
	curRef := ctx.getCurrentRef()
	ctx.addClassRef(elem.Class, curRef)
	ctx.addReferent(elem.Referent)
	ctx.incCurrentRef()
	inst := Instance{
		ClassId:    ctx.getCurrentClassId(),
		ClassName:  elem.Class,
		Ref:        curRef,
		Attributes: map[string]Attribute{},
		Tags:       []string{},
		Properties: map[string]Property{},
		Children:   []*Instance{},
	}
	for _, prop := range elem.Properties.List {
		DecodePropXML(prop, &inst, ctx)
	}
	for _, ins := range elem.Children {
		inst.Children = append(inst.Children, buildTree(ctx, ins))
	}
	return &inst
}

func DecodePropXML(prop *XMLProperty, inst *Instance, ctx *RbxmxContext) error {
	outputProp := Property{
		Type:  prop.Name,
		Value: prop.Value,
	}
	switch prop.XMLName.Local {
	case "bool":
		outputProp.Type = "boolean"
		outputProp.Value = prop.Value == "true"
	case "string":
		outputProp.Type = "string"
		outputProp.Value = prop.Value
		outputProp.Encoded = false
	case "ProtectedString":
		outputProp.Type = "string"
		outputProp.Value = prop.Value
		outputProp.Encoded = false
	case "BinaryString":
		outputProp.Type = "string"
		outputProp.Value = prop.Value
		outputProp.Encoded = true
	case "int":
		val, err := strconv.ParseInt(prop.Value, 10, 0)
		if err != nil {
			return err
		}
		outputProp.Value = val
		outputProp.Type = "int32"
		if prop.Name == "BrickColor" {
			outputProp.Type = "brickcolor"
		}
	case "int64":
		val, err := strconv.ParseInt(prop.Value, 10, 64)
		if err != nil {
			return err
		}
		outputProp.Value = val
		outputProp.Type = "int64"
	case "float":
		val, err := strconv.ParseFloat(prop.Value, 64)
		if err != nil {
			return err
		}
		outputProp.Value = PurifyFloatValue(val)
		outputProp.Type = "rbxf32"
	case "token":
		val, err := strconv.ParseInt(prop.Value, 10, 0)
		if err != nil {
			return err
		}
		outputProp.Value = val
		outputProp.Type = "enum"
	case "Content":
		decodeContent(&outputProp, prop)
	case "ContentId":
		decodeContent(&outputProp, prop)
	case "Color3uint8":
		decodeColor3uint8(&outputProp, prop.Value)
	case "Color3":
		decodeColor3(&outputProp, prop)
	case "CoordinateFrame":
		decodeCFrame(&outputProp, prop)
	case "Vector2":
		decodeVector2(&outputProp, prop)
	case "Vector3":
		decodeVector3(&outputProp, prop)
	case "Font":
		decodeFont(&outputProp, prop)
	case "UDim":
		decodeUDim(&outputProp, prop)
	case "UDim2":
		decodeUDim2(&outputProp, prop)
	case "NumberSequence":
		decodeNumberSeq(&outputProp, prop)
	case "ColorSequence":
		decodeColorSeq(&outputProp, prop)
	case "Rect2D":
		min := find(prop, "min")
		max := find(prop, "max")
		if min == nil || max == nil {
			return fmt.Errorf("%s", "Invalid Rect property!")
		}
		pos1, err := decodeVector2(&Property{}, min)
		if err != nil {
			return fmt.Errorf("%v", err.Error())
		}
		pos1Value := pos1.Value
		pos2, err := decodeVector2(&Property{}, max)
		if err != nil {
			return fmt.Errorf("%v", err.Error())
		}
		pos2Value := pos2.Value
		outputProp = Property{
			Type: "rect",
			Value: Rect{
				Position1: pos1Value.([]float32),
				Position2: pos2Value.([]float32),
			},
		}
	case "Ray":
		min := find(prop, "origin")
		max := find(prop, "direction")
		if min == nil || max == nil {
			return fmt.Errorf("%s", "Invalid Ray property!")
		}
		pos1, err := decodeVector3(&Property{}, min)
		if err != nil {
			return fmt.Errorf("%v", err.Error())
		}
		pos1Value := pos1.Value
		pos2, err := decodeVector3(&Property{}, max)
		if err != nil {
			return fmt.Errorf("%v", err.Error())
		}
		pos2Value := pos2.Value
		outputProp = Property{
			Type: "rect",
			Value: Ray{
				Origin:    pos1Value.([]float32),
				Direction: pos2Value.([]float32),
			},
		}
	case "PhysicalProperties":
		decodePhysProps(&outputProp, prop)
	case "NumberRange":
		decodeNumberRange(&outputProp, prop)
	case "SharedString":
		outputProp.Value = ctx.SharedStrings[ctx.getSharedString(prop.Value)]
		outputProp.Type = "sharedstr"
	case "Ref":
		decodeRef(&outputProp, prop, ctx)
	}
	if outputProp.Value != nil {
		inst.Properties[prop.Name] = outputProp
	}
	return nil
}
func find(prop *XMLProperty, name string) *XMLProperty {
	for _, c := range prop.Children {
		if c.XMLName.Local == name {
			return &c
		}
	}
	return nil
}
func decodeContent(ret *Property, prop *XMLProperty) *Property {
	if len(prop.Children) > 0 {
		switch prop.Children[0].XMLName.Local {
		case "url":
			ret.Type = "string"
			ret.Value = prop.Children[0].Value
		case "uri":
			ret.Type = "string"
			ret.Value = prop.Children[0].Value
		case "null":
			ret.Value = ""
		}
	}
	return ret
}
func decodeColor3uint8(ret *Property, rawStr string) ([3]uint8, error) {
	raw, err := strconv.Atoi(rawStr)
	if err != nil {
		return [3]uint8{}, err
	}
	values := [3]uint8{
		uint8((raw >> 16) & 0xFF),
		uint8((raw >> 8) & 0xFF),
		uint8(raw & 0xFF),
	}
	ret.Value = values
	ret.Type = "rgbc3"
	return values, nil
}
func decodeCFrame(ret *Property, prop *XMLProperty) (*Property, error) {

	X, Y, Z := find(prop, "X"), find(prop, "Y"), find(prop, "Z")

	if X == nil || Y == nil || Z == nil {
		return nil, fmt.Errorf("invalid CFrame: missing X/Y/Z")
	}

	xval, _ := strconv.ParseFloat(strings.TrimSpace(X.Value), 64)
	yval, _ := strconv.ParseFloat(strings.TrimSpace(Y.Value), 64)
	zval, _ := strconv.ParseFloat(strings.TrimSpace(Z.Value), 64)

	keys := []string{"R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"}
	rotation := make([]float64, 9)

	for i, key := range keys {
		elem := find(prop, key)
		if elem == nil {
			return nil, fmt.Errorf("invalid CFrame: missing %s", key)
		}
		val, _ := strconv.ParseFloat(strings.TrimSpace(elem.Value), 64)
		rotation[i] = val
	}
	ret.Value = map[string]any{
		"position": map[string]any{
			"vector3": []float64{PurifyFloatValue(xval), PurifyFloatValue(yval), PurifyFloatValue(zval)},
		},
		"rotation": rotation,
	}
	ret.Type = "cframe"
	return ret, nil
}
func decodeVector2(ret *Property, prop *XMLProperty) (*Property, error) {
	X, Y := find(prop, "X"), find(prop, "Y")
	if X == nil || Y == nil {
		return nil, fmt.Errorf("invalid Vector2: missing X/Y")
	}
	xval, err := strconv.ParseFloat(strings.TrimSpace(X.Value), 32)
	yval, err := strconv.ParseFloat(strings.TrimSpace(Y.Value), 32)
	if err != nil {
		return ret, err
	}
	ret.Type = "vector2"
	ret.Value = []float32{PurifyFloat32Value(float32(xval)), PurifyFloat32Value(float32(yval))}
	return ret, nil
}
func decodeVector3(ret *Property, prop *XMLProperty) (*Property, error) {
	X, Y, Z := find(prop, "X"), find(prop, "Y"), find(prop, "Z")
	if X == nil || Y == nil {
		return nil, fmt.Errorf("invalid Vector3: missing X/Y/Z")
	}
	xval, err := strconv.ParseFloat(strings.TrimSpace(X.Value), 32)
	yval, err := strconv.ParseFloat(strings.TrimSpace(Y.Value), 32)
	zval, err := strconv.ParseFloat(strings.TrimSpace(Z.Value), 32)
	if err != nil {
		return ret, err
	}
	ret.Type = "vector3"
	ret.Value = []float64{PurifyFloatValue(xval), PurifyFloatValue(yval), PurifyFloatValue(zval)}
	return ret, nil
}
func decodeUDim(ret *Property, prop *XMLProperty) (*Property, error) {
	S, O := find(prop, "S"), find(prop, "O")
	if S == nil || O == nil {
		return nil, fmt.Errorf("invalid UDim: missing S/O")
	}
	sval, err := strconv.ParseFloat(strings.TrimSpace(S.Value), 32)
	oval, err := strconv.ParseInt(strings.TrimSpace(O.Value), 10, 32)
	if err != nil {
		return ret, err
	}
	ret.Type = "udim"
	ret.Value = UDim{
		Scale:  PurifyFloat32Value(float32(sval)),
		Offset: int(oval),
	}
	return ret, nil
}
func decodeUDim2(ret *Property, prop *XMLProperty) (*Property, error) {
	SX, OX := find(prop, "XS"), find(prop, "XO")
	SY, OY := find(prop, "YS"), find(prop, "YO")
	if SX == nil || OX == nil || SY == nil || OY == nil {
		return nil, fmt.Errorf("invalid UDim2: missing SX/OX/SY/OY")
	}
	sxval, err := strconv.ParseFloat(strings.TrimSpace(SX.Value), 32)
	oxval, err := strconv.ParseInt(strings.TrimSpace(OX.Value), 10, 32)
	syval, err := strconv.ParseFloat(strings.TrimSpace(SY.Value), 32)
	oyval, err := strconv.ParseInt(strings.TrimSpace(OY.Value), 10, 32)
	if err != nil {
		return ret, err
	}
	ret.Type = "udim2"
	ret.Value = UDim2{
		X: UDim{
			Scale:  PurifyFloat32Value(float32(sxval)),
			Offset: int(oxval),
		},
		Y: UDim{
			Scale:  PurifyFloat32Value(float32(syval)),
			Offset: int(oyval),
		},
	}
	return ret, nil
}
func decodeFont(ret *Property, prop *XMLProperty) (*Property, error) {
	family, weight, style := find(prop, "Family"), find(prop, "Weight"), find(prop, "Style")
	styleInt := 0
	if family == nil || weight == nil || style == nil {
		return nil, fmt.Errorf("invalid Font: missing Family/Weight/Style")
	}
	fontStyle := strings.TrimSpace(style.Value)
	switch fontStyle {
	case "Normal":
		styleInt = 0
	case "Italic":
		styleInt = 1
	}
	weightInt, err := strconv.ParseInt(weight.Value, 10, 32)
	if err != nil {
		return nil, err
	}
	var prp Property
	decodeContent(&prp, family)
	ret.Value = Font{
		FontFamily: prp.Value.(string),
		FontWeight: int(weightInt),
		FontStyle:  styleInt,
	}
	return ret, nil
}
func decodeRef(ret *Property, prop *XMLProperty, ctx *RbxmxContext) (*Property, error) {
	value := prop.Value
	if !strings.HasPrefix(value, "RBX") {
		ret.Value = -1
	} else {
		ret.Value = ctx.getRefFromReferent(value)
	}
	ret.Type = "ref"
	return ret, nil
}
func decodePhysProps(ret *Property, prop *XMLProperty) (*Property, error) {
	d, f, e, fw, ew, aa := 0.0, 0.5, 0.0, 1.0, 1.0, 1.0
	defines := find(prop, "CustomPhysics")
	if defines == nil || strings.TrimSpace(defines.Value) != "true" {
		ret.Value = nil
	} else {
		de, fe, ee, fwe, ewe, aae := find(prop, "Density"), find(prop, "Friction"), find(prop, "Elasticity"), find(prop, "FrictionWeight"), find(prop, "ElasticityWeight"), find(prop, "AcousticAbsorption")
		if de != nil {
			v, err := strconv.ParseFloat(de.Value, 64)
			if err != nil {
				return ret, err
			}
			d = v

		}
		if fe != nil {
			v, err := strconv.ParseFloat(fe.Value, 64)
			if err != nil {
				return ret, err
			}
			f = v
		}
		if ee != nil {
			v, err := strconv.ParseFloat(ee.Value, 64)
			if err != nil {
				return ret, err
			}
			e = v
		}
		if fwe != nil {
			v, err := strconv.ParseFloat(fwe.Value, 64)
			if err != nil {
				return ret, err
			}
			fw = v
		}
		if ewe != nil {
			v, err := strconv.ParseFloat(ewe.Value, 64)
			if err != nil {
				return ret, err
			}
			ew = v
		}
		if aae != nil {
			v, err := strconv.ParseFloat(aae.Value, 64)
			if err != nil {
				return ret, err
			}
			aa = v
		}
		ret.Value = [6]float64{PurifyFloatValue(d), PurifyFloatValue(f), PurifyFloatValue(e), PurifyFloatValue(fw), PurifyFloatValue(ew), PurifyFloatValue(aa)}
	}
	ret.Type = "physprops"
	return ret, nil
}
func decodeNumberRange(ret *Property, prop *XMLProperty) (*Property, error) {
	value_stream := strings.TrimSpace(prop.Value)
	if value_stream == "" {
		ret.Value = []float64{0.0, 0.0}
	}
	values_string := strings.Split(value_stream, " ")
	numVals := len(values_string)
	if numVals < 2 {
		return ret, fmt.Errorf("invalid Number Range! Not enough elements!")
	}
	values := make([]float64, numVals)
	for i := 0; i < numVals; i++ {
		v, err := strconv.ParseFloat(values_string[i], 64)
		if err != nil {
			return ret, err
		}
		values[i] = PurifyFloatValue(v)
	}
	ret.Value = values
	ret.Type = "numberrange"
	return ret, nil
}
func decodeNumberSeq(ret *Property, prop *XMLProperty) error {
	valueCount := 3
	values := strings.Split(prop.Value, " ")
	keypointCount := len(values) / valueCount
	keypoints := make([]map[string]any, keypointCount)
	for k := 0; k < keypointCount; k++ {
		keypoint := make([]float64, valueCount)
		for i := 0; i < valueCount; i++ {
			valueIndex := (k * valueCount) + i
			val, err := strconv.ParseFloat(values[valueIndex], 64)
			if err != nil {
				return fmt.Errorf("%s", "Failed to parse NumberSequence: A value specified is invalid.")
			}
			keypoint[i] = PurifyFloatValue(val)
		}
		keypoints[k] = map[string]any{
			"nskp": keypoint,
		}
	}
	ret.Type = "numbersequence"
	ret.Value = keypoints
	return nil
}
func decodeColorSeq(ret *Property, prop *XMLProperty) error {
	valueCount := 5
	values := strings.Split(prop.Value, " ")
	keypointCount := len(values) / valueCount
	keypoints := make([]map[string]any, keypointCount)
	for k := 0; k < keypointCount; k++ {
		keypoint := make([]float64, valueCount)
		for i := 0; i < valueCount; i++ {
			valueIndex := (k * valueCount) + i
			val, err := strconv.ParseFloat(values[valueIndex], 64)
			if err != nil {
				return fmt.Errorf("%s", "Failed to parse ColorSequence: A value specified is invalid.")
			}
			keypoint[i] = PurifyFloatValue(val)
		}
		keypoints[k] = map[string]any{
			"cskp": map[string]any{
				"t":      keypoint[0],
				"color3": []float64{keypoint[1], keypoint[2], keypoint[3]},
			},
		}
	}
	ret.Type = "colorsequence"
	ret.Value = keypoints
	return nil
}
func decodeColor3(ret *Property, prop *XMLProperty) error {
	r, g, b := find(prop, "R"), find(prop, "G"), find(prop, "B")
	if r == nil || g == nil || b == nil {
		return fmt.Errorf("%s", "Invalid Color3 property!")
	}
	rf, err := strconv.ParseFloat(r.Value, 64)
	gf, err := strconv.ParseFloat(g.Value, 64)
	bf, err := strconv.ParseFloat(b.Value, 64)
	if err != nil {
		return err
	}
	ret.Type = "rgbc3"
	ret.Value = []float64{PurifyFloatValue(rf) * 255, PurifyFloatValue(gf) * 255, PurifyFloatValue(bf) * 255}
	return nil
}
