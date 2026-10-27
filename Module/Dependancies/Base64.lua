--!optimize 2

local base64={};
local encodingService=game:GetService("EncodingService");
local buffer_fromstring=buffer.fromstring;
local buffer_tostring=buffer.tostring;
function base64.encode(data)
    return buffer_tostring(encodingService:Base64Encode(buffer_fromstring(data)));
end;

function base64.decode(data)
    return buffer_tostring(encodingService:Base64Decode(buffer_fromstring(data)));
end;
return base64;