import os
import sys
import glob


def main():
    tag_ref = sys.argv[1]
    tag = tag_ref.split('/')[-1].split('v')[-1]
    out_dir = os.path.normpath(os.path.join(os.getcwd(), 'out'))
    miz_full_path = glob.glob(os.path.join(out_dir, '*.miz'))[0]
    assert (os.path.exists(miz_full_path))
    root, miz_name = os.path.split(miz_full_path[:-len('.miz')])
    new_miz_name = ''.join([miz_name, f'-v{tag}', '.miz'])

    new_full_path = os.path.join(out_dir, new_miz_name)
    os.rename(miz_full_path, new_full_path)


if __name__ == '__main__':
    main()
