import os
import struct
import time
from pathlib import Path

class AssembleEngine:
    def __init__(self):
        self.exefilename = ''
        self.basedirectory = ''
        self.detectioncode = b'2E23E563-31FA-4C24-B7B3-90BE720C6B1A'
        self.startheader = b'DXGBD7F1BE4-9FCF-4E3A-ABA7-3443D11AB362'
        self.endheader = b'DXG1C58841C-D8A0-4457-BF54-D8315D4CF49D'
        self.filemask = '*'
        self.filelist = []

    def prepare_file_list(self, directory):
        for root, dirs, files in os.walk(directory):
            for file in files:
                if self.filemask == '*' or file.endswith(self.filemask):
                    self.filelist.append(os.path.join(root, file))

    def find_signature(self, signature, file_stream):
        file_stream.seek(0)
        buffer = file_stream.read()
        return buffer.find(signature) != -1

    def try_open_exe_stream(self):
        max_tries = 10
        tries = 1
        while True:
            try:
                return open(self.exefilename, 'r+b')
            except IOError as e:
                if tries >= max_tries:
                    raise e
                tries += 1
                time.sleep(1)

    def stream_write_raw(self, stream, line):
        stream.write(line)

    def stream_write_int64(self, stream, value):
        stream.write(struct.pack('q', value))

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
            if not self.find_signature(self.detectioncode, strm):
                raise ValueError("Signature not found in .exe file. Please ensure the .exe file is compiled with the correct libraries.")

            if self.find_signature(self.startheader, strm) or self.find_signature(self.endheader, strm):
                raise ValueError("This file has already been modified. Please recompile the .exe file.")

            strm.seek(0, os.SEEK_END)
            self.stream_write_raw(strm, self.startheader)
            relative_offset_helper = strm.tell()

            for file in self.filelist:
                print(f"Adding file: {file}")
                with open(file, 'rb') as infile:
                    file_offset = strm.tell()
                    file_size = os.path.getsize(file)
                    strm.write(infile.read())
                    self.filelist.append({'filename': file, 'offset': file_offset, 'size': file_size})

            strm.seek(0, os.SEEK_END)
            table_offset = strm.tell()
            for file_info in self.filelist:
                relative_offset = file_info['offset'] - relative_offset_helper
                self.stream_write_int64(strm, relative_offset)
                self.stream_write_int64(strm, file_info['offset'] - relative_offset_helper)
                self.stream_write_int64(strm, file_info['size'])
                relative_path = os.path.relpath(file_info['filename'], self.basedirectory)
                self.stream_write_raw(strm, relative_path.encode('utf-8'))

            self.stream_write_int64(strm, table_offset - relative_offset_helper)
            self.stream_write_raw(strm, self.endheader)

        print(f"Successfully added {len(self.filelist)} files to {self.exefilename}")

# Example usage
engine = AssembleEngine()
engine.exefilename = 'path_to_your_exe_file.exe'
engine.basedirectory = 'path_to_your_locale_directory'
engine.execute()
