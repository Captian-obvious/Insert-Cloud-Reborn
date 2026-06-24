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

return parser;
