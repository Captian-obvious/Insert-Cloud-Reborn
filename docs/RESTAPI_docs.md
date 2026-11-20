---
title: REST API Reference
description: Reference document for API endpoints on the Insert Webservice
category: Documentation
tags: [Documentation, REST API, Reference, REST API Reference, API Reference]
authors:
    - Captian-obvious (aka Superduperdev2)
---
# Prerequisites
Understanding this document requires some prior knowledge with what a RESTful API is and how to<br/>
interact with one. It also assumes a basic understanding of data types:
- `int`: Integer<br/>
- `float`: Float32/Float64 (decimal)<br/>
- *etc*

## Base URL

    https://ic-siwebservices.com

## VALID ASSET TYPES (SO FAR)
- `Model` - A Model Asset (returns [**JSON Instance Tree**](#json-instance-tree) or [**RBXM**](https://dom.rojo.space/binary.html) depending on endpoint)
- `Audio` - An Audio Asset (returned as `audio/ogg`)
- `Mesh` - A Mesh Asset (returned as `text/plain`)
- `Image` - An Image Asset (returned as `image/png`)
- `AvatarAsset` - An avatar item/accessory with identical format to `Model`
- `MeshHiddenSurfaceRemoval` - A `HiddenSurfaceRemovalAsset` used by Roblox to store HSR data for layered clothing (returns same as `Model`)
- `SolidModel` - A `PartOperationAsset` used by Roblox to store `UnionOperation` data remotely. (returns same as `Model`)
- `MeshPart` - A `MeshPart` asset with identical format to `Model`
- `Decal` - Stores a decal (returns same as `Model`)

## Legend
<span style="color: #ff0000">*</span>Required<br/>

## Data Structures
This Document mentions some data structures that are not the same as other REST APIs, Here is a<br/>
list:
### JSON Instance Tree
[**JSON**](https://www.rfc-editor.org/rfc/rfc8259) representation of an [**RBXM**](https://dom.rojo.space/binary.html). The below is typical structure and does not reflect any<br/>
real asset, real assets have actual Roblox properties such as "Material" and "CFrame"<br/>
```json
{
    "metadata":{
        "ExplicitAutoJoints":true
    },
    "instance_count":2,
    "class_count":2,
    "tree":[
        {
            "class_name":"SomeClass",
            "ref":0,
            "attributes":{
                "SomeAttribute":{
                    "type":"string",
                    "value":"type specific, this example is a string that isn't encoded in base64",
                    "enc":false
                }
            },
            "properties":{
                "SomeProperty":{
                    "type":"string",
                    "value":"type specific, once again this is a string that isnt encoded",
                    "enc":false
                },
                "SomeOtherProperty":{
                    "type":"rbxf32",
                    "value":0.0
                }
            },
            "children":[
                {
                    "class_name":"SomeOtherClass",
                    "ref":1,
                    "attributes":{},
                    "properties":{
                        "AnotherProperty":{
                            "type":"rbxf32",
                            "value":0.0
                        }
                    },
                    "children":[],
                    "class_id":1
                }
            ],
            "class_id":0
        }
    ]
}
```
### FileMesh
In house mesh format of Roblox, its file extension is listed with its conversion<br/>
and it's listed here again: `.mesh`<br/>

The FileMesh format is a sort of mix of text and binary. Its file header is always one of these 10<br/>
- `version 1.00\n`
- `version 1.01\n`
- `version 2.00\n`
- `version 3.00\n`
- `version 3.01\n`
- `version 4.00\n`
- `version 4.01\n`
- `version 5.00\n`
- `version 6.00\n`
- `version 7.00\n`

Every version beyond `1.01` is binary. These have conventions such as FACs data and skinning.<br/>
`version 6.00\n` and beyond use a chunks format, while previous versions just list each part of the<br/>
mesh.



# Fetch Endpoints

**MOST OF THESE ENDPOINTS SUPPORT THE HEADER `x-api-key`!!**<br/>
**IT IS RECOMMENDED YOU PROVIDE YOUR OWN `x-api-key` HEADER <br/>
TO AVOID RATE LIMITS ON THE PRIMARY DEFAULT ONE!**

## `GET /api/v3/asset/<assetId:int>`
Fetches an asset from Roblox's Asset Storage and parses formats that are not standard into standard formats.<br/>
Supports all `AssetType`s that are [**RBXM**](https://dom.rojo.space/binary.html) (`Model`,`AvatarAsset`,etc) & supports `Image`s, `Mesh`es,<br/>
and `Audio`<br/>
### Conversions Currently Supported:
- [**RBXM**](https://dom.rojo.space/binary.html) ⇒ [**JSON Instance Tree**](#json-instance-tree)
- [**FileMesh (`.mesh`)**](#filemesh) ⇒ Wavefront `.obj` file

### Parameters
- `assetId`<span style="color: #ff0000">*</span> (url): ID of the asset you want to fetch.
- `placeId`<span style="color: #ff0000">*</span> (query): ID of the place you are loading from, usually this is just `game.PlaceId` from the Module
- `version` (query): Version number (defaults to latest version)
- `type` (query): Roblox Asset Type (defaults to `Model`) {Refer to [Valid Asset Types](#valid-asset-types-so-far) for valid types (and returned `Content-Type`)}
- `isSolidModel` <span style="color: #ff0000">DEPRECATED</span> (query): Whether or not the asset is a `SolidModel`,<br/>
This is deprecated in favor of `type=SolidModel` as it functions identically.<br/>

### Responses:
- 200 OK - Asset Resource fetched successfully
- 400 BAD REQUEST - Request sent was invalid.
- 401 UNAUTHORIZED - API Key provided is invalid or expired.
- 403 FORBIDDEN - User is not authorized to access asset.
- 409 CONFLICT - There was a conflict with permissions to access asset.
- 500 INTERNAL SERVER ERROR - Asset failed to decompile (parse).

```bash
# Fetch Model as a JSON Instance Tree
curl "https://ic-siwebservices.com/api/v3/asset/15098485774?placeId=7081918890"

# With your own API key (recommended, avoids the shared rate limit)
curl -H "x-api-key: YOUR_API_KEY" \
    "https://ic-siwebservices.com/api/v3/asset/15098485774?placeId=7081918890"

# Fetch a Mesh, converted to .obj
curl -H "x-api-key: YOUR_API_KEY" \
    "https://ic-siwebservices.com/api/v3/asset/123456789?placeId=987654321&type=Mesh" \
    --output mesh.obj

# With a specific version
curl "https://ic-siwebservices.com/api/v3/asset/15098485774?placeId=7081918890&version=1"
```

## `GET /api/v2/asset/<assetId:int>` (LEGACY)
Fetches an asset (in [**RBXM**](https://dom.rojo.space/binary.html)) from Roblox's Asset Storage and returns the [**JSON Instance Tree**](#json-instance-tree), only `Model`s are supported<br/>
### Parameters
- `assetId`<span style="color: #ff0000">*</span> (url): ID of the asset you want to fetch.
- `placeId`<span style="color: #ff0000">*</span> (query): ID of the place you are loading from, usually this is just `game.PlaceId` from the Module
- `version` (query): Version number (defaults to latest version)

### Responses:
- 200 OK - Asset Resource fetched successfully
- 400 BAD REQUEST - Request sent was invalid.
- 401 UNAUTHORIZED - API Key provided is invalid or expired.
- 403 FORBIDDEN - User is not authorized to access asset.
- 409 CONFLICT - There was a conflict with permissions to access asset.
- 500 INTERNAL SERVER ERROR - Asset failed to decompile (parse).

```bash
curl "https://ic-siwebservices.com/api/v2/asset/15098485774?placeId=7081918890"
```

## `GET /api/v1/asset/<assetId:int>` (LEGACY, Upgraded)
Fetches an asset from Roblox's Asset Storage and directly returns its data, previously<br/>
only `Model`s were supported, but changes in the backend allowed support for other `AssetType`s<br/>
### Parameters
- `assetId`<span style="color: #ff0000">*</span> (url): ID of the asset you want to fetch.
- `placeId`<span style="color: #ff0000">*</span> (query): ID of the place you are loading from, usually this is just `game.PlaceId` from the Module
- `version` (query): Version number (defaults to latest version)
- `type` (query): Roblox Asset Type (defaults to `Model`) {Refer to [Valid Asset Types](#valid-asset-types-so-far) for valid types (and returned `Content-Type`)}

### Responses:
- 200 OK - Asset Resource fetched successfully
- 400 BAD REQUEST - Request sent was invalid.
- 401 UNAUTHORIZED - API Key provided is invalid or expired.
- 403 FORBIDDEN - User is not authorized to access asset.
- 409 CONFLICT - There was a conflict with permissions to access asset.

```bash
# Returns asset data raw
curl "https://ic-siwebservices.com/api/v1/asset/15098485774?placeId=7081918890" \
    --output model.rbxm
```

# Additional Endpoints

## `POST /api/v3/public/parse`
Parse an [**RBXM**](https://dom.rojo.space/binary.html) Stream into a [**JSON Instance Tree**](#json-instance-tree);<br/>
Useful to parse any [**RBXM**](https://dom.rojo.space/binary.html) Stream into its<br/> [**JSON Instance Tree**](#json-instance-tree)<br/>
### Parameters
- Request `body`<span style="color: #ff0000">*</span>: Base64 encoded [**RBXM**](https://dom.rojo.space/binary.html) stream to parse

### Responses
- 200 OK - Stream decompiled (parsed) successfully.
- 400 BAD REQUEST - Request sent was invalid.
- 500 INTERNAL SERVER ERROR - Failed to decompile (parse) stream.

```bash
# Base64-encode a local .rbxm and send it as the request body (non-mac)
base64 -w 0 model.rbxm | curl -X POST \
  --data-binary @- \
  "https://ic-siwebservices.com/api/v3/public/parse"
# Mac
base64 -i model.rbxm | curl -X POST \
  --data-binary @- \
  "https://ic-siwebservices.com/api/v3/public/parse"
```