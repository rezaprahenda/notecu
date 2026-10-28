<p align="center"><img src="Resources/AppIcon.png" width="96" alt="notecu"></p>

<h1 align="center">notecu</h1>
<p align="center"><i>note it, cu later.</i></p>

**notecu** (*notes lucu*) adalah app catatan di sisi layar untuk macOS. Panelnya muncul dari tepi layar saat kursor didorong ke pinggir (atau lewat ⌃⌥N), jadi kamu bisa mencatat tanpa meninggalkan app yang sedang dipakai.

Semua data tersimpan **di Mac ini saja**. Tanpa akun, tanpa server, tanpa internet.

## Fitur

- **Catatan** dengan judul, folder, warna penanda, sematan, dan `#tag`
- **Agenda harian**: satu kartu per topik rapat, dikelompokkan per tanggal → bulan → tahun, dengan kerangka Peserta / Pembahasan / Kesimpulan / Tindak lanjut
- **To-do** dengan tenggat, jam, penting ★, folder, tag, pengingat, dan **to-do berulang**
- **Kalimat to-do pintar**: `Surati Kapusdatin besok 10:00 ! #kementan` → tenggat besok jam 10, penting, bertag
- **Tautan antar catatan** `[[Judul]]`, lengkap dengan daftar *Disebut di*
- **To-do terkait** di bawah catatan (dibuat dari catatan, ikut folder & tag-nya)
- **Rahasia 🔒**: blok teks lalu ⌘L, atau kunci seluruh catatan. Dienkripsi AES-256-GCM (kunci PBKDF2-SHA256, 210.000 putaran)
- **Ringkasan** untuk laporan bulanan: agenda, to-do selesai & yang masih berjalan, per jenis atau per tag
- Checklist `- [ ]`, poin, daftar bernomor, `# Judul`, **tebal**, *miring*, `kode`, dan link yang bisa diklik
- Sampah 30 hari, cadangan & pemulihan JSON, jalankan saat login

## Kebutuhan

- macOS 14 Sonoma atau lebih baru
- Command Line Tools (`xcode-select --install`). Xcode tidak diperlukan.

## Build & pasang

```bash
git clone <url-repo-ini> notecu
cd notecu
./build.sh install     # build, pasang ke /Applications, lalu jalankan
```

Pilihan lain: `./build.sh` (build saja) atau `./build.sh run` (build lalu jalankan dari folder `build/`).

App ditandatangani *ad-hoc*. Kalau macOS menolak membukanya pertama kali, klik kanan **notecu.app → Open**.

## Pintasan

| Pintasan | Fungsi |
|---|---|
| ⌃⌥N | Buka / tutup panel dari mana saja |
| ⌃⌥⇧N | Catatan baru dari mana saja |
| ⌃⌥T | To-do baru dari mana saja |
| ⌘N / ⌘D / ⌘T | Catatan / agenda / to-do baru (di dalam panel) |
| ⌘F | Cari |
| ⌘L | Rahasiakan teks yang diblok |
| ⌘[ | Kembali ke daftar |
| Esc / ⌘W | Tutup panel |

## Saat menulis to-do

| Tulis | Hasil |
|---|---|
| `hari ini`, `besok`, `lusa` | tenggat |
| `jumat`, `senin depan`, `hari minggu`, `minggu depan` | tenggat |
| `tgl 5`, `3/11`, `akhir bulan`, `awal bulan depan`, `3 hari lagi`, `sebulan lagi` | tenggat |
| `10:00`, `jam 14`, `9.30`, `besok sore`, `nanti malam` | jam |
| `tiap senin`, `tiap hari`, `tiap hari kerja`, `tiap tgl 25`, `tiap bulan` | berulang |
| `!` | penting |
| `#tag` | tag |

## Data

- Lokasi: `~/Library/Application Support/notecu/cache.json`
- Cadangan: **Pengaturan → Umum → Data → Simpan cadangan (JSON)**. Pulihkan dari menu yang sama.
- Kata sandi rahasia tidak disimpan di mana pun. **Kalau lupa, isi yang terkunci tidak bisa dibuka.**

## Struktur

```
Sources/
  App.swift             menu bar, hotkey global, jendela pengaturan
  PanelController.swift panel dari tepi layar, shortcut di dalam panel
  PanelViews.swift      tampilan panel: daftar, editor, agenda, tautan
  NoteStore.swift       data & penyimpanan lokal
  Models.swift          bentuk data, aturan teks
  Tasks.swift           to-do, kalimat to-do, to-do berulang
  TaskViews.swift       tampilan to-do
  Tags.swift            #tag
  Vault.swift           rahasia & catatan terkunci
  Summary.swift         ringkasan bulanan
  Reminders.swift       pengingat lewat Notification Center
  NoteTextView.swift    editor teks (NSTextView)
  SettingsView.swift    pengaturan
build.sh                build tanpa Xcode
```

## Lisensi

[MIT](LICENSE) © 2026 Reza Prahenda

---

made with ♥ by [@rezaprahenda](https://instagram.com/rezaprahenda)
