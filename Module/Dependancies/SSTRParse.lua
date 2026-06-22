local parser={
    Services={
        ReplicatedStorage=game:GetService("ReplicatedStorage"),
        InsertService=game:GetService("InsertService"),
    },
    modules={
        b64=require(script.Parent.Base64), --b64
    },
};

function parser:ParseSharedStr(sstr)
    local actualString=self.modules.b64.decode(sstr);
    return actualString;
end;

local function shapeFromPrimative(primative)
    local shapeMap={
        ["Block"]=Enum.PartType.Block,
        ["Cylinder"]=Enum.PartType.Cylinder,
        ["Ball"]=Enum.PartType.Ball,
        ["Wedge"]=Enum.PartType.Wedge,
        ["CornerWedge"]=Enum.PartType.CornerWedge,
    };
    return shapeMap[primative.rawShape] or Enum.PartType.Block;
end;

function parser:ParseMeshDataToModel(meshData)
    local model=Instance.new("Model");
    model.Name="ParsedModel";
    for _,partData in pairs(meshData.Parts) do
        local part=Instance.new("Part");
        part.Name=partData.Name or "Part";
        part.Size=Vector3.new(partData.Size.X,partData.Size.Y,partData.Size.Z);
        part.Position=Vector3.new(partData.Position.X,partData.Position.Y,partData.Position.Z);
        part.Orientation=Vector3.new(partData.Orientation.X,partData.Orientation.Y,partData.Orientation.Z);
        part.Color=Color3.new(partData.Color.R,partData.Color.G,partData.Color.B);
        part.Shape=shapeFromPrimative(partData.Shape);
        part.Transparency=partData.Transparency or 0;
        part.Anchored=true;
        part.Parent=model;
        if partData.Mesh then
            local mesh=Instance.new("SpecialMesh");
            mesh.MeshType=Enum.MeshType.FileMesh;
            mesh.MeshId=partData.Mesh.MeshId;
            if partData.Mesh.TextureId then
                mesh.TextureId=partData.Mesh.TextureId;
            end;
            if partData.Mesh.Scale then
                mesh.Scale=Vector3.new(partData.Mesh.Scale.X,partData.Mesh.Scale.Y,partData.Mesh.Scale.Z);
            end;
            mesh.Parent=part;
        end;
    end;
    model.Parent=self.Services.ReplicatedStorage; -- Or wherever you want to store the model
    return model;
end;

return parser;
