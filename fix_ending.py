def add_padding(stream, align_to=256, padding_char=b'\x20'):
    current_position = stream.tell()
    padding_needed = (align_to - (current_position % align_to)) % align_to
    stream.write(padding_char * padding_needed)

def execute(self):
    if not self.exefilename:
        raise ValueError("No .exe filename specified.")
    if not self.basedirectory:
        self.basedirectory = os.path.dirname(self.exefilename)

    self.prepare_file_list(self.basedirectory)
    if not self.filelist:
        print(f"No files matching '{self.filemask}' found in '{self.basedirectory}', leaving the executable unchanged.")
        return

    self.filelist.sort()

    with self.try_open_exe_stream() as strm:
        if self.find_signature(self.detectioncode, strm) == -1:
            raise ValueError("Signature not found in .exe file. Please ensure the .exe file is compiled with the correct libraries.")
        if self.find_signature(self.startheader, strm) != -1 or self.find_signature(self.endheader, strm) != -1:
            raise ValueError("This file has already been modified. Please recompile the .exe file.")

        strm.seek(0, os.SEEK_END)
        self.write_raw(strm, self.startheader)
        relative_offset_helper = strm.tell()

        for file in self.filelist:
            print(f"Adding file: {file}")
            with open(file, 'rb') as infile:
                file_offset = strm.tell()
                file_size = os.path.getsize(file)
                strm.write(infile.read())
                self.filelist.append({'filename': file, 'offset': file_offset, 'size': file_size})
                self.add_padding(strm)

        strm.seek(0, os.SEEK_END)
        table_offset = strm.tell()

        next_pos = table_offset
        for file_info in self.filelist:
            while strm.tell() != next_pos:
                self.write_raw(strm, b' ')

            next_pos = ((strm.tell() + 8 + 8 + 8 + len(file_info['filename']) + 1) + 256) & ~0xFF
            self.write_int64(strm, next_pos - relative_offset_helper)
            self.write_int64(strm, file_info['offset'] - relative_offset_helper)
            self.write_int64(strm, file_info['size'])
            relative_path = f"locale/{os.path.relpath(file_info['filename'], self.basedirectory)}"
            print(f"Adding Header: {relative_path}")
            self.write_raw(strm, relative_path.encode('utf-8') + b'\0')

        while strm.tell() != next_pos:
            self.write_raw(strm, b' ')

        self.write_int64(strm, 0)
        self.write_raw(strm, self.endheader)

    print(f"Successfully added {len(self.filelist)} files to {self.exefilename}")
