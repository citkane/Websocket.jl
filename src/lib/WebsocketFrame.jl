struct WebsocketFrame
    maskBytes::IOBuffer
    frameHeader::IOBuffer   
    inf::Dict{Symbol, Any}
    addData::Function
    function WebsocketFrame(
        maskBytes::IOBuffer,
        frameHeader::IOBuffer,
        binaryPayload::Array{UInt8, 1} = Array{UInt8, 1}()
    )
        inf = Dict{Symbol, Any}(
            :fin => false,
            :mask => false,
            :opcode => 0x00,
            :rsv1 => 0x00,
            :rsv2 => 0x00,
            :rsv3 => 0x00,
            :length => 0x00,
            :parseState => DECODE_HEADER,
            :binaryPayload => binaryPayload
        )

        self = new(
            maskBytes,
            frameHeader,
            inf,
            data::Array{UInt8,1} -> addData(self, data)
        )
    end
end

function toBuffer(frame::WebsocketFrame)
    inf = (; frame.inf...)

    headerLength = 2
    firstByte = 0x00
    secondByte = 0x00
    len = 0
    

    inf.fin && (firstByte |= 0x80)
    inf.mask && (secondByte |= 0x80)
    firstByte |= (inf.opcode & 0x0F)

    if inf.opcode === CONNECTION_CLOSE_FRAME
        len = length(inf.binaryPayload) + 2
        closeStatus = statusbuffer(inf.closeStatus)
        pushfirst!(inf.binaryPayload, closeStatus...)
    else
        len = length(inf.binaryPayload)
    end

    if len <= 125
        secondByte |= (len & 0x7F)
    elseif len > 125 && len <= 0xFFFF
        secondByte |= 126
        headerLength += 2
    elseif len > 0xFFFF
        secondByte |= 127
        headerLength += 8
    end

    size = len + headerLength + (inf.mask ? 4 : 0)
    output = IOBuffer(Array{UInt8, 1}(undef, size);
        maxsize = size,
        read = true,
        write = true
    )
    header = [UInt8(firstByte), UInt8(secondByte)]
    write(output, header)

    if len > 125 && len <= 0xFFFF

    elseif len > 0xFFFF

    end

    if inf.mask
        maskKey = newMask()
        seek(frame.maskBytes, 0)
        write(frame.maskBytes, maskKey)
        write(output, maskKey)
        mask!(maskKey, inf.binaryPayload)
        write(output, inf.binaryPayload)
    elseif len > 0

    end
    seek(output, 0)
    output
end

function addData(self::WebsocketFrame, payload::Array{UInt8,1})
    inf = self.inf
    if inf[:parseState] === DECODE_HEADER
        firstByte = payload[1]
        secondByte = payload[2]
        
        inf[:fin] = firstByte & WS_FINAL > 0
        inf[:mask] = secondByte & WS_MASK > 0
        inf[:opcode] = firstByte & WS_OPCODE
        inf[:length] = secondByte & WS_LENGTH
        inf[:rsv1] = firstByte & WS_RSV1 > 0
        inf[:rsv2] = firstByte & WS_RSV2 > 0
        inf[:rsv3] = firstByte & WS_RSV3 > 0

        inf[:parseState] = WAITING_FOR_MASK_KEY
    end
    if inf[:parseState] === WAITING_FOR_MASK_KEY
        if inf[:mask] && size(payload, 1) >= 4
            throw(error("TODO: extract mask"))
        end
        inf[:parseState] = WAITING_FOR_PAYLOAD
    end
    if inf[:parseState] === WAITING_FOR_PAYLOAD
        len = size(payload, 1)
        if len >= inf[:length]
            index = (len - inf[:length])
            if inf[:opcode] === CONNECTION_CLOSE_FRAME
                index += 2
                inf[:closeStatus] = statusint(payload[index-1 : index])
            end
            inf[:binaryPayload] = payload[index + 1:len]
            inf[:mask] && mask!(inf[:binaryPayload], self.maskBytes)

            inf[:parseState] = COMPLETE
            return true
        end
    end
    return false
end
