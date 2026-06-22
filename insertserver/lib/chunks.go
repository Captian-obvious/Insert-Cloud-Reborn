package lib

import (
	"encoding/base64"
	"encoding/binary"
	"errors"
)

func bool_from_string(s string) bool {
	if s == "true" {
		return true
	} else {
		return false
	}
}

func META(data *Stream, rbxm *RBXM) error {
	var num uint32
	data.ReadNumber(binary.LittleEndian, &num)
	for i := 0; i < int(num); i++ {
		k := RbxString(data)
		v := RbxString(data)
		if k == "ExplicitAutoJoints" {
			rbxm.Metadata[k] = bool_from_string(v)
		} else {
			rbxm.Metadata[k] = v
		}
	}
	return nil
}

func SSTR(data *Stream, rbxm *RBXM) error {
	var nums [2]uint32
	data.ReadNumber(binary.LittleEndian, &nums)
	ver, num := nums[0], nums[1]
	if ver != 0 {
		return errors.New("Invalid SSTR version.")
	}
	rbxm.SharedStrings = make([]string, num)
	for i := 0; i < int(num); i++ {
		data.Read(16, true) //md5 hash (useless for RBXM)
		rbxm.SharedStrings[i] = base64.StdEncoding.EncodeToString([]byte(RbxString(data)))
	}
	return nil
}
func INST(data *Stream, rbxm *RBXM) error {
	var classId uint32
	data.ReadNumber(binary.LittleEndian, &classId)
	className := RbxString(data)
	if data.ReadAsString(1, true) == "\x01" {
		return errors.New("Attempt to insert binary model with services")
	}
	var refCount uint32
	data.ReadNumber(binary.LittleEndian, &refCount)
	refs := RefArray(data, int(refCount))
	rbxm.ClassRef[classId] = ClassRefEntry{
		Name:   className,
		Sizeof: int(refCount),
		Refs:   refs,
	}
	for _, ref := range refs {
		rbxm.InstRef[ref] = &Instance{
			Attributes: map[string]Attribute{},
			ClassId:    int(classId),
			ClassName:  className,
			Ref:        ref,
			Properties: map[string]Property{},
			Tags:       []string{},
			Children:   []*Instance{},
		}
	}
	return nil
}

func PROP(data *Stream, rbxm *RBXM) error {
	var classId uint32
	data.ReadNumber(binary.LittleEndian, &classId)
	classRef := rbxm.ClassRef[classId]
	refs := classRef.Refs
	sizeof := classRef.Sizeof
	propName := RbxString(data)
	if propName == "WorldPivotInternal" {
		return nil
	}
	optTypeIdCheck := data.Read(1, false)[0] == 0x1E
	if optTypeIdCheck {
		data.Seek(1)
	}
	typeId := data.Read(1, true)[0]
	props, err := DecodeProp(data, typeId, sizeof, rbxm)
	if err != nil {
		return err
	}
	for i := 0; i < len(refs); i++ {
		v := refs[i]
		inst := rbxm.InstRef[v]
		_prop := props[i]
		if propName == "AttributesSerialize" {
			inst.Attributes = ParseAttributesValue(_prop)
			continue
		} else if propName == "Tags" {
			inst.Tags = ParseTagsValue(_prop)
			continue
		} else if _prop.Value == nil {
			continue
		}
		inst.Properties[propName] = _prop
	}
	return nil
}

func PRNT(data *Stream, rbxm *RBXM) error {
	if data.ReadAsString(1, true) != "\x00" {
		return errors.New("Invalid PRNT version")
	}
	var num uint32
	data.ReadNumber(binary.LittleEndian, &num)
	childRefs := RefArray(data, int(num))
	parentRefs := RefArray(data, int(num))
	for i := 0; i < int(num); i++ {
		childId := childRefs[i]
		parentId := parentRefs[i]
		child := rbxm.InstRef[childId]
		//fmt.Printf("Parent %d -> Child %d\n", parentId, childId)
		if parentId != -1 {
			parent := rbxm.InstRef[parentId]
			parent.Children = append(parent.Children, child)
		} else {
			rbxm.Tree = append(rbxm.Tree, child)
		}
	}
	return nil
}
