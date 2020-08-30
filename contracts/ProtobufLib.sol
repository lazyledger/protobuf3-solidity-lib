// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.6.0 <8.0.0;

library ProtobufLib {
    /// @notice Protobuf wire types.
    enum WireType { Varint, Bits64, LengthDelimited, StartGroup, EndGroup, Bits32 }

    /// @notice Maximum number of bytes for a varint.
    /// @notice 64 bits, in groups of base-128 (7 bits).
    uint256 public constant MAX_VARINT_BYTES = 10;

    ////////////////////////////////////
    // Decoding
    ////////////////////////////////////

    /// @notice Decode key.
    /// @dev https://developers.google.com/protocol-buffers/docs/encoding#structure
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Field number
    /// @return Wire type
    function decode_key(uint256 p, bytes memory buf)
        internal
        pure
        returns (
            uint256,
            uint64,
            WireType
        )
    {
        // The key is a varint with encoding
        // (field_number << 3) | wire_type
        (uint256 pos, uint64 key) = decode_varint(p, buf);
        uint64 field_number = key >> 3;
        WireType wire_type = WireType(key & 0x07);

        // Start and end group types are deprecated, so forbid them
        require(wire_type != WireType.StartGroup && wire_type != WireType.EndGroup);

        return (pos, field_number, wire_type);
    }

    /// @notice Decode varint.
    /// @dev https://developers.google.com/protocol-buffers/docs/encoding#varints
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded int
    function decode_varint(uint256 p, bytes memory buf) internal pure returns (uint256, uint64) {
        uint64 val;
        uint256 i;

        for (i = 0; i < MAX_VARINT_BYTES; i++) {
            // Get byte at offset
            uint8 b = uint8(buf[p + i]);

            // Highest bit is used to indicate if there are more bytes to come
            // Mask to get 7-bit value: 0111 1111
            uint8 v = b & 0x7F;

            // Groups of 7 bits are ordered least significant first
            val |= uint64(v) << uint64(i * 7);

            // Mask to get keep going bit: 1000 0000
            if (b & 0x80 == 0) {
                require(v != 0, "varint has trailing zeroes");
                break;
            }
        }

        require(i < MAX_VARINT_BYTES, "varint used more than MAX_VARINT_BYTES bytes");

        // If all 10 bytes are used, the last byte (most significant 7 bits)
        // must be at most 0000 0001, since 7*9 = 63
        if (i == MAX_VARINT_BYTES - 1) {
            require(uint8(buf[p + i]) <= 1, "varint uses more than 64 bits");
        }

        return (p + i + 1, val);
    }

    /// @notice Decode varint uint32.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded int
    function decode_uint32(uint256 p, bytes memory buf) internal pure returns (uint256, uint32) {
        (uint256 pos, uint64 val) = decode_varint(p, buf);

        // Highest 4 bytes must be 0
        require(val & 0xFFFFFFFF00000000 == 0);

        return (pos, uint32(val));
    }

    /// @notice Decode varint uint64.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded int
    function decode_uint64(uint256 p, bytes memory buf) internal pure returns (uint256, uint64) {
        (uint256 pos, uint64 val) = decode_varint(p, buf);

        return (pos, val);
    }

    /// @notice Decode Boolean.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded bool
    function decode_bool(uint256 p, bytes memory buf) internal pure returns (uint256, bool) {
        (uint256 pos, uint64 val) = decode_varint(p, buf);

        if (val == 1) {
            return (pos, true);
        }

        return (pos, false);
    }

    /// @notice Decode enumeration.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded enum as raw int
    function decode_enum(uint256 p, bytes memory buf) internal pure returns (uint256, uint64) {
        return decode_uint64(p, buf);
    }

    /// @notice Decode fixed 64-bit int.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded int
    function decode_bits64(uint256 p, bytes memory buf) internal pure returns (uint256, uint64) {
        uint64 val;

        for (uint256 i = 0; i < 8; i++) {
            uint8 b = uint8(buf[p + i]);

            // Little endian
            val |= uint64(b) << uint64(i * 8);
        }

        return (p + 8, val);
    }

    /// @notice Decode fixed uint64.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded int
    function decode_fixed64(uint256 p, bytes memory buf) internal pure returns (uint256, uint64) {
        (uint256 pos, uint64 val) = decode_bits64(p, buf);

        return (pos, val);
    }

    /// @notice Decode fixed 32-bit int.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded int
    function decode_bits32(uint256 p, bytes memory buf) internal pure returns (uint256, uint32) {
        uint32 val;

        for (uint256 i = 0; i < 4; i++) {
            uint8 b = uint8(buf[p + i]);

            // Little endian
            val |= uint32(b) << uint32(i * 8);
        }

        return (p + 4, val);
    }

    /// @notice Decode fixed uint32.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded int
    function decode_fixed32(uint256 p, bytes memory buf) internal pure returns (uint256, uint32) {
        (uint256 pos, uint32 val) = decode_bits32(p, buf);

        return (pos, val);
    }

    /// @notice Decode length-delimited field.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Field bytes
    function decode_length_delimited(uint256 p, bytes memory buf) internal pure returns (uint256, bytes memory) {
        // Length-delimited fields begin with a varint of the number of bytes that follow
        (uint256 pos, uint64 size) = decode_varint(p, buf);

        bytes memory field = new bytes(size);
        for (uint256 i = 0; i < size; i++) {
            field[i] = buf[pos + i];
        }

        return (pos + size, field);
    }

    /// @notice Decode string.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Decoded string
    function decode_string(uint256 p, bytes memory buf) internal pure returns (uint256, string memory) {
        (uint256 pos, bytes memory field) = decode_length_delimited(p, buf);

        return (pos, string(field));
    }

    /// @notice Decode bytes array.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Field bytes
    function decode_bytes(uint256 p, bytes memory buf) internal pure returns (uint256, bytes memory) {
        (uint256 pos, bytes memory field) = decode_length_delimited(p, buf);

        return (pos, field);
    }

    /// @notice Decode embedded message.
    /// @param p Position
    /// @param buf Buffer
    /// @return New position
    /// @return Field bytes
    function decode_embedded_message(uint256 p, bytes memory buf) internal pure returns (uint256, bytes memory) {
        (uint256 pos, bytes memory field) = decode_length_delimited(p, buf);

        return (pos, field);
    }

    ////////////////////////////////////
    // Encoding
    ////////////////////////////////////

    ////////////////////////////////////
    // Helpers
    ////////////////////////////////////
}
