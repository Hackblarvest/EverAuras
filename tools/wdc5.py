"""Minimal reader for WoW's WDC5 client database files (.db2), enough for EverAuras' generators.

Handles the header, sections, field storage (none, bitpacked, common data, pallet, pallet array,
bitpacked signed), id lists, copy tables, relationship maps (parent ids), sparse records and inline
strings. Rows come back as lists of raw per-field values (arrays as lists); what a field means comes
from WoWDBDefs (https://github.com/wowdev/WoWDBDefs), matched by the file's layout hash.
"""
import struct


class Field:
    def __init__(self, offset_bits, size_bits, add_size, storage, v1, v2, v3):
        self.offset_bits, self.size_bits, self.add_size = offset_bits, size_bits, add_size
        self.storage, self.v1, self.v2, self.v3 = storage, v1, v2, v3


def _bits(data, bit_offset, bit_count):
    byte = bit_offset >> 3
    shift = bit_offset & 7
    nbytes = (shift + bit_count + 7) >> 3
    v = int.from_bytes(data[byte:byte + nbytes], "little")
    return (v >> shift) & ((1 << bit_count) - 1)


def read(path):
    b = open(path, "rb").read()
    assert b[:4] == b"WDC5", b[:4]
    o = 4 + 4 + 128
    (rc, fc, rs, sts, table_hash, layout_hash, min_id, max_id, locale, flags, id_index,
     total_fc, bp_off, lookup_cols, fsi_size, common_size, pallet_size, section_count) = struct.unpack_from("<9I2H7I", b, o)
    o += struct.calcsize("<9I2H7I")
    sections = []
    for _ in range(section_count):
        sec = struct.unpack_from("<Q8I", b, o)
        o += struct.calcsize("<Q8I")
        sections.append(dict(zip(["key", "file_offset", "record_count", "string_table_size", "offset_records_end",
                                  "id_list_size", "relationship_data_size", "offset_map_id_count", "copy_table_count"], sec)))
    structs = []
    for _ in range(fc):
        size, off = struct.unpack_from("<hH", b, o)
        o += 4
        structs.append((size, off))
    fields = []
    for _ in range(fsi_size // 24):
        fields.append(Field(*struct.unpack_from("<HHIIIII", b, o)))
        o += 24
    pallet = b[o:o + pallet_size]
    o += pallet_size
    common_raw = b[o:o + common_size]
    o += common_size

    # per-field slices of pallet / common data
    pal_off, com_off, commons = [], 0, []
    p = 0
    for f in fields:
        if f.storage in (3, 4):
            pal_off.append(p)
            p += f.add_size
        else:
            pal_off.append(None)
    for f in fields:
        if f.storage == 2:
            m = {}
            for k in range(f.add_size // 8):
                rid, val = struct.unpack_from("<II", common_raw, com_off + k * 8)
                m[rid] = val
            commons.append(m)
            com_off += f.add_size
        else:
            commons.append(None)

    sparse = bool(flags & 1)
    rows = {}
    parents = {}
    starts = {}
    gindex = {}          # rid -> record index across all sections (strings are addressed that way)
    blob = bytearray()   # all sections' string tables, concatenated
    base = 0
    for sec in sections:
        so = sec["file_offset"]
        n = sec["record_count"]
        if sec["key"] != 0 and sec["file_offset"] == 0:
            continue
        rec_data = []
        if not sparse:
            data_start = so
            for i in range(n):
                rec_data.append((data_start + i * rs, rs))
            string_start = so + n * rs
            after = string_start + sec["string_table_size"]
            blob += b[string_start:after]
        else:
            after = sec["offset_records_end"]
            string_start = None
        # id list
        ids = list(struct.unpack_from("<%dI" % (sec["id_list_size"] // 4), b, after)) if sec["id_list_size"] else []
        after += sec["id_list_size"]
        copies = [struct.unpack_from("<II", b, after + k * 8) for k in range(sec["copy_table_count"])]
        after += sec["copy_table_count"] * 8
        if sparse:
            offmap = [struct.unpack_from("<IH", b, after + k * 6) for k in range(sec["offset_map_id_count"])]
            after += sec["offset_map_id_count"] * 6
            rec_data = [(off, size) for off, size in offmap]
        rel = {}
        if sec["relationship_data_size"]:
            num, rmin, rmax = struct.unpack_from("<3I", b, after)
            for k in range(num):
                fid, ridx = struct.unpack_from("<II", b, after + 12 + k * 8)
                rel[ridx] = fid
            after += sec["relationship_data_size"]
        if sparse and sec["offset_map_id_count"]:
            ids = list(struct.unpack_from("<%dI" % sec["offset_map_id_count"], b, after))
        for i, (start, size) in enumerate(rec_data):
            rec = b[start:start + size]
            if not any(rec):
                continue   # encrypted section without its key
            vals = []
            for fi, f in enumerate(fields):
                vals.append(_value(rec, f, fi, pallet, pal_off, commons, ids[i] if ids else None, start, b,
                                   string_start, sparse))
            rid = ids[i] if ids else vals[id_index]
            if not ids and isinstance(rid, list):
                rid = rid[0]
            rows[rid] = vals
            starts[rid] = start
            gindex[rid] = base + i
            if i in rel:
                parents[rid] = rel[i]
        for new_id, old_id in copies:
            if old_id in rows:
                rows[new_id] = list(rows[old_id])
                starts[new_id] = starts[old_id]
                gindex[new_id] = gindex[old_id]
                if old_id in parents:
                    parents[new_id] = parents[old_id]
        base += n
    total_records = sum(sec["record_count"] for sec in sections) * rs
    return dict(gindex=gindex, blob=bytes(blob), total_records=total_records, layout_hash=layout_hash, rows=rows, parents=parents, starts=starts, data=b, fields=fields, id_index=id_index,
                record_size=rs, flags=flags, structs=structs)


def _value(rec, f, fi, pallet, pal_off, commons, rid, rec_start, b, string_start, sparse):
    st = f.storage
    if st == 0:
        nbytes = f.size_bits // 8
        start = f.offset_bits // 8
        if nbytes > 4 and nbytes % 4 == 0:
            return [struct.unpack_from("<I", rec, start + k * 4)[0] for k in range(nbytes // 4)]
        return int.from_bytes(rec[start:start + nbytes], "little")
    if st == 1 or st == 5:
        v = _bits(rec, f.offset_bits, f.size_bits)
        if st == 5 and v & (1 << (f.size_bits - 1)):
            v -= 1 << f.size_bits
        return v
    if st == 2:
        return commons[fi].get(rid, f.v1)
    if st == 3:
        idx = _bits(rec, f.offset_bits, f.size_bits)
        return struct.unpack_from("<I", pallet, pal_off[fi] + idx * 4)[0]
    if st == 4:
        idx = _bits(rec, f.offset_bits, f.size_bits)
        cnt = f.v3
        return [struct.unpack_from("<I", pallet, pal_off[fi] + (idx * cnt + k) * 4)[0] for k in range(cnt)]
    raise ValueError("storage %d" % st)


def signed32(v):
    return v - (1 << 32) if isinstance(v, int) and v >= 1 << 31 else v


def string_at(t, rid, field_index):
    """An inline string field of a dense table: offset from the field's position in the virtual
    concatenation [all records][all string tables]."""
    f = t["fields"][field_index]
    pos = t["gindex"][rid] * t["record_size"] + f.offset_bits // 8 + t["rows"][rid][field_index] - t["total_records"]
    end = t["blob"].index(0, pos)
    return t["blob"][pos:end].decode("utf-8", "replace")

if __name__ == "__main__":
    import sys
    t = read(sys.argv[1])
    print("layout %08X rows %d parents %d fields %d" % (t["layout_hash"], len(t["rows"]), len(t["parents"]), len(t["fields"])))
    for i, f in enumerate(t["fields"]):
        print("  field %d: off %d bits %d storage %d v=(%d,%d,%d) add=%d" % (i, f.offset_bits, f.size_bits, f.storage, f.v1, f.v2, f.v3, f.add_size))
    for rid in sorted(t["rows"])[:5]:
        print("  row", rid, t["rows"][rid], "parent", t["parents"].get(rid))

