package com.mizani.money.core.legal

enum class LegalDocumentId { TERMS, PRIVACY }

data class LegalSection(
    val heading: String,
    val paragraphs: List<String>,
)

data class LegalDocument(
    val id: LegalDocumentId,
    val title: String,
    val version: String,
    val effectiveDate: String,
    val introduction: String,
    val sections: List<LegalSection>,
)

/**
 * User-facing legal drafts. Keep the matching Markdown copies in docs/ aligned with these
 * sections. Versions identify legal-document revisions and are independent of app releases.
 * Increment one only when that document's user-facing legal meaning changes; existing users then
 * accept the revised document once before opening their ledger.
 */
object LegalDocuments {
    const val EFFECTIVE_DATE = "19 November 2026"
    const val PRIVACY_EFFECTIVE_DATE = "19 November 2026"
    const val TERMS_VERSION = "2026-11-19-1"
    const val PRIVACY_VERSION = "2026-11-19-1"
    const val PRIVACY_CONTACT = "paul.ochieng.dev@gmail.com"
    const val PROVIDER_NAME = "Nyota Foundry"
    const val PROVIDER_ADDRESS = "Kampala, Uganda"

    val terms = LegalDocument(
        id = LegalDocumentId.TERMS,
        title = "Syarat Layanan",
        version = TERMS_VERSION,
        effectiveDate = EFFECTIVE_DATE,
        introduction =
            "Syarat ini berlaku saat kamu memasang atau memakai Catatan Keuangan. Dengan mengetuk “Setuju dan lanjutkan” " +
                "saat pengaturan awal, atau setelah menerima versi baru di aplikasi, kamu setuju dengan Syarat ini. " +
                "Baca dulu sebelum melanjutkan.",
        sections = listOf(
            LegalSection("1. Penyedia dan kontak", listOf(
                "Penyedia: $PROVIDER_NAME. Alamat: $PROVIDER_ADDRESS. Kontak: $PRIVACY_CONTACT.",
            )),
            LegalSection("2. Siapa yang boleh memakai Catatan Keuangan", listOf(
                "Kamu harus bisa membuat perjanjian yang mengikat menurut hukum di tempat tinggalmu. Jika kamu " +
                    "belum cukup umur untuk bertindak secara hukum, pakai Catatan Keuangan hanya dengan izin orang tua atau wali hukum.",
            )),
            LegalSection("3. Apa yang disediakan aplikasi", listOf(
                "Catatan Keuangan adalah alat pribadi untuk mengatur anggaran dan mencatat keuangan. Alat ini membantu " +
                    "kamu mengelola informasi keuangan yang kamu pilih untuk dimasukkan, termasuk catatan manual investasi, dan " +
                    "melihat ringkasan di HP kamu. Aplikasi ini bukan bank, " +
                    "layanan pembayaran, pemberi pinjaman, penasihat investasi, layanan penilaian kredit, layanan akuntansi, " +
                    "atau layanan pajak. Aplikasi tidak memindahkan, menyimpan, atau menjaga uang untukmu. Catatan investasi " +
                    "tidak terhubung ke penyedia, tidak memasang order, dan tidak mengubah saldo dompet.",
                "Aplikasi tidak memberikan nasihat keuangan, investasi, hukum, akuntansi, atau pajak. Tampilannya " +
                    "bukan rekomendasi atau janji bahwa dana akan tersedia. Periksa keputusan penting dengan catatanmu sendiri " +
                    "dan nasihat profesional yang sesuai.",
            )),
            LegalSection("4. Informasimu dan perangkat", listOf(
                "Catatan Keuangan tidak menyimpan salinan online catatan keuanganmu. Catatan itu terenkripsi dan disimpan " +
                    "di HP kamu. Kamu bertanggung jawab mengamankan perangkat dan menjaga ekspor serta cadangan " +
                    "tetap aman. Pemberitahuan Privasi menjelaskan pengecekan kurs dan pembaruan yang bersifat opsional.",
                "Catatan Keuangan memakai pengaturan jendela aman Android untuk memblokir tangkapan layar biasa, rekaman layar, " +
                    "dan tangkapan di layar yang tidak aman. Kontrol platform ini tidak bisa menghentikan kamera atau " +
                    "perangkat yang sudah disusupi, dan perilakunya bergantung pada Android dan pabrikan perangkat.",
                "Catatan Keuangan mengaktifkan pengingat harian secara default saat pengaturan awal. Kamu bisa mengubah atau mematikannya di Pengaturan. " +
                    "Jika aktif, Catatan Keuangan memeriksa catatan di HP ini dan bisa menampilkan notifikasi umum jika " +
                    "tidak ada pemasukan, pengeluaran, atau pengembalian yang tercatat hari itu. Aplikasi tidak mengirim catatanmu ke " +
                    "layanan pengingat mana pun.",
                "Masukkan informasi yang berhak kamu pakai. Hindari memasukkan detail sensitif orang lain " +
                    "di kolom penerima atau catatan, kecuali kamu punya alasan yang sah dan izin untuk itu.",
            )),
            LegalSection("5. Konversi mata uang", listOf(
                "Jika kamu mencatat transaksi dalam mata uang yang berbeda dari mata uang ruang kerja, Catatan Keuangan mungkin " +
                    "meminta kurs acuan harian terbaru untuk pasangan mata uang tersebut dari Frankfurter. " +
                    "Permintaan hanya berisi kode mata uang, bukan nominal, penerima, catatan, atau tanggal transaksi. " +
                    "Aplikasi menyimpan kurs dan tanggal publikasinya bersama transaksi yang dikonversi.",
                "Kurs acuan bisa tertunda, direvisi, tidak tersedia, atau berbeda dari kurs yang dipakai oleh " +
                    "bank, jaringan kartu, penukaran uang tunai, atau penyedia pembayaran. Kurs ini tidak termasuk biaya " +
                    "atau selisih. Periksa konversi yang ditampilkan dan perbaiki jika perlu. Jangan mengandalkannya untuk " +
                    "penyelesaian, perdagangan, pajak, atau pelaporan regulasi.",
            )),
            LegalSection("6. Tanggung jawabmu", listOf(
                "Kamu bertanggung jawab atas keakuratan dan penggunaan yang sah dari informasi yang kamu masukkan, untuk " +
                    "memeriksa hasil aplikasi, dan untuk setiap keputusan keuangan. Jangan menyalahgunakan aplikasi, mengganggu " +
                    "keamanannya, atau memakainya dengan cara yang melanggar hukum yang berlaku atau hak orang lain.",
            )),
            LegalSection("7. Ekspor dan cadangan", listOf(
                "Ekspor CSV dan buku Excel bisa dibaca manusia dan tidak terenkripsi. Buku Excel " +
                    "berisi beberapa lembar catatan keuanganmu untuk analisis. Cadangan Catatan Keuangan dienkripsi " +
                    "dengan frasa sandi yang kamu pilih; jika frasa sandi itu hilang, cadangan tidak bisa dipulihkan. " +
                    "Berkas yang kamu simpan di luar Catatan Keuangan bisa disalin, dicadangkan, atau diproses oleh layanan tujuan " +
                    "sesuai ketentuannya sendiri. Aplikasi tidak bisa menghapus salinan di luar penyimpanan pribadinya.",
                "Cadangan perangkat otomatis dinonaktifkan. Menghapus semua data lokal tidak bisa dibatalkan tanpa " +
                    "cadangan. Menghapus Catatan Keuangan bisa menghilangkan catatanmu secara permanen. Ekspor cadangan dulu " +
                    "jika ingin menyimpan salinannya.",
            )),
            LegalSection("8. Hak aplikasi dan perubahan", listOf(
                "Syarat ini mengatur pemakaian rilis resmi aplikasi Catatan Keuangan. Hak untuk memakai, mengubah, dan mendistribusikan " +
                    "kode sumber dan bentuk eksekusi Catatan Keuangan yang tercakup diberikan di bawah Lisensi Apache, " +
                    "Versi 2.0, sebagaimana dijelaskan di berkas LICENSE dan NOTICE repositori; Syarat ini tidak " +
                    "mempersempit hak tersebut. Lisensi itu tidak memberi hak atas nama, logo, atau materi pihak ketiga " +
                    "Mizani, yang tetap tunduk pada pemberitahuan dan ketentuannya sendiri.",
                "Kami dapat memperbarui, mengubah, atau menghentikan fitur aplikasi. Jika perubahan merevisi Syarat ini secara material, " +
                    "aplikasi akan menampilkan Syarat yang direvisi dan meminta kamu menyetujuinya sebelum lanjut memakai " +
                    "aplikasi. Kamu bisa berhenti memakai Catatan Keuangan dan menghapus data lokal kapan saja.",
            )),
            LegalSection("9. Batasan layanan dan hak hukum", listOf(
                "Catatan Keuangan disediakan tanpa janji bahwa aplikasi akan selalu tersedia, bebas kesalahan, atau cocok " +
                    "untuk setiap perangkat atau tujuan. Sejauh diizinkan hukum, penyedia tidak bertanggung jawab " +
                    "atas kerugian tidak langsung akibat mengandalkan entri, ringkasan, kurs konversi, kehilangan perangkat, atau " +
                    "ekspor. Tidak ada bagian Syarat ini yang membatasi hak atau upaya hukum yang tidak boleh kami batasi " +
                    "menurut hukum yang berlaku, termasuk perlindungan konsumen yang wajib.",
            )),
            LegalSection("10. Hukum yang berlaku dan pertanyaan", listOf(
                "Ketentuan hukum wajib yang berlaku di tempat tinggalmu tetap berlaku. Pilihan hukum dalam draf ini " +
                    "tidak menghapus perlindungan tersebut. Untuk pertanyaan tentang Syarat ini, hubungi $PRIVACY_CONTACT.",
            )),
        ),
    )

    val privacy = LegalDocument(
        id = LegalDocumentId.PRIVACY,
        title = "Pemberitahuan Privasi",
        version = PRIVACY_VERSION,
        effectiveDate = PRIVACY_EFFECTIVE_DATE,
        introduction =
            "Pemberitahuan ini menjelaskan bagaimana Catatan Keuangan menyimpan informasimu dan pilihan yang kamu miliki.",
        sections = listOf(
            LegalSection("1. Siapa yang bertanggung jawab", listOf(
                "Penyedia: $PROVIDER_NAME. Alamat: $PROVIDER_ADDRESS. Kontak: $PRIVACY_CONTACT.",
            )),
            LegalSection("2. Informasi yang disimpan di perangkatmu", listOf(
                "Informasi yang kamu masukkan bisa mencakup nama dompet dan saldo; jenis transaksi, tanggal, " +
                    "nominal, biaya, mata uang, penerima, dan catatan; anggaran dan kategori; sumber pemasukan; target " +
                    "dan kontribusi; item berulang; catatan utang; serta catatan investasi manual seperti " +
                    "nama aset, penyedia atau lokasi, kategori aset secara umum, modal, nilai saat ini, " +
                    "tanggal penilaian, dan catatan. Kolom nama dan catatan bebas bisa memuat informasi pribadi jika " +
                    "kamu memasukkannya di sana.",
                "Jika kamu memilih untuk menempel atau membagikan konfirmasi dompet digital yang didukung, Catatan Keuangan membaca teksnya " +
                    "di HP ini. Pesan asli dibuang setelah ditinjau; hanya transaksi yang kamu konfirmasi dan " +
                    "nomor referensi penyedianya yang disimpan di catatanmu.",
                "Catatan Keuangan juga menyimpan pengaturan seperti negara yang dipilih, mata uang utama, tema, dan kunci aplikasi, " +
                    "pengingat harian (aktif secara default saat pengaturan awal) beserta waktunya, pengaturan pengecekan " +
                    "keuangan yang opsional, dan kurs mata uang yang disimpan sementara. Detail kunci aplikasi tetap di HP " +
                    "ini. Aplikasi mencatat versi dokumen-dokumen ini yang kamu setujui dan kapan kamu menyetujuinya.",
            )),
            LegalSection("3. Mengapa aplikasi memakai informasi ini", listOf(
                "Catatan Keuangan memakai informasimu untuk menyediakan fitur anggaran yang kamu pilih, melindungi catatanmu, " +
                    "dan membuat ekspor atau cadangan saat kamu memintanya. Pengingat harian aktif secara default " +
                    "saat pengaturan awal, tetapi bisa dimatikan; aplikasi memeriksa catatan lokalmu dan memakai notifikasi umum " +
                    "tanpa nama atau nominal. Pengingat komitmen dan pengecekan uang yang opsional bekerja dengan cara yang sama. " +
                    "Tidak ada pengingat ini yang mengirim informasi catatan keluar dari HP. Pengecekan uang adalah " +
                    "pertanyaan deskriptif, bukan nasihat investasi, utang, atau keuangan lainnya.",
                "Catatan Keuangan tidak meminta nama, alamat email, nomor telepon, login bank, atau akun. Catatanmu " +
                    "tidak dipakai untuk iklan atau pelacakan pemakaian.",
                "Jika kamu memilih Kirim masukan, Catatan Keuangan membuka aplikasi email di perangkatmu dengan pesanmu " +
                    "dialamatkan ke tim Catatan Keuangan. Aplikasi tidak melampirkan catatan atau mengirim pesan itu sendiri. " +
                    "Penyedia emailmu menerima apa pun yang kamu kirim dan mengatur pengiriman serta filter spam.",
            )),
            LegalSection("4. Permintaan opsional", listOf(
                "Saat kamu mengonversi transaksi mata uang asing atau target komitmen, Catatan Keuangan mengirim dua " +
                    "kode mata uang ke Frankfurter untuk mendapatkan kurs acuan terbaru yang tersedia. Permintaan ini tidak mengirim nominal, tanggal, " +
                    "penerima, catatan, nama dompet, atau detail catatan lainnya. Kurs dan tanggalnya disimpan bersama " +
                    "transaksi atau komitmen di HP kamu.",
                "Frankfurter menyatakan tidak mengumpulkan atau mencatat data pribadi, alamat IP, atau detail permintaan. Penyedia jaringanmu " +
                    "tetap menangani koneksinya. Baca selengkapnya di https://frankfurter.dev/.",
                "Jika kamu memasang Catatan Keuangan di luar Google Play, kamu bisa memilih memeriksa pembaruan. Catatan Keuangan meminta " +
                    "informasi rilis publik dari GitHub dan membandingkan versi rilis dengan perangkatmu. Aplikasi " +
                    "tidak mengirim versi yang terpasang atau catatanmu. GitHub bisa menerima alamat IP dan detail " +
                    "permintaanmu sesuai Pernyataan Privasi mereka. Kamu bisa melewati pengecekan ini.",
                "Saat Catatan Keuangan dipasang dari Google Play, layanan pembaruan dalam aplikasi Play bisa memeriksa versi aplikasi, " +
                    "modul yang terpasang, dan metadata perangkat untuk menentukan apakah ada rilis Play dan seberapa besar ukurannya. " +
                    "Google Play mengatur unduhan dan pemasangan; Catatan Keuangan tidak mengirim catatan atau detail keuangan " +
                    "untuk pengecekan ini. Permintaan pembaruan ditampilkan saat aplikasi sedang aktif.",
                "Saat kamu memakai Kirim masukan, aplikasi email yang kamu pilih bisa memproses dan menyimpan pesan itu " +
                    "sesuai ketentuannya sendiri. Pesan masukan berisi teks yang kamu tulis dan informasi dasar versi Catatan Keuangan " +
                    "dan Android; pesan tidak berisi nominal transaksi, saldo, nama dompet, atau data cadangan kecuali kamu menuliskannya sendiri.",
            )),
            LegalSection("5. Penyimpanan, keamanan, dan retensi", listOf(
                "Catatan keuanganmu terenkripsi dan disimpan di HP ini. Keamanan perangkat membantu melindungi " +
                    "akses ke catatan tersebut. Tidak ada langkah keamanan yang bisa menjamin perangkat atau data aman dalam setiap keadaan.",
                "Catatan Keuangan memasang proteksi jendela aman Android di layar, dialog, dan menu aplikasi untuk memblokir " +
                    "tangkapan layar biasa, rekaman layar, dan tangkapan tampilan yang tidak aman. Perilaku Android dan perangkat " +
                    "berbeda-beda; ini tidak bisa mencegah tangkapan dengan kamera eksternal atau di perangkat yang sudah disusupi.",
                "Catatan Keuangan tidak menyimpan salinan online buku besarmu. Catatan lokal tetap di aplikasi sampai kamu menghapus semua " +
                    "data lokal, menghapus penyimpanan aplikasi, atau menghapus aplikasinya. Menghapus semua data juga menghapus kurs mata uang " +
                    "yang tersimpan, pengaturan, dan jadwal pengingat. Cadangan perangkat otomatis dinonaktifkan. " +
                    "Menghapus aplikasi atau kehilangan akses ke HP ini bisa membuat data lokal tidak bisa dipulihkan.",
            )),
            LegalSection("6. Ekspor dan layanan lain", listOf(
                "Ekspor CSV dan buku Excel tidak terenkripsi dan bisa membuka detail keuanganmu kepada siapa pun " +
                    "yang bisa mengakses berkas itu. CSV adalah ekspor buku transaksi; buku Excel dan " +
                    "cadangan terenkripsi juga mencakup catatan investasi manual. Buku Excel memuat beberapa lembar " +
                    "seperti transaksi, dompet, investasi, anggaran, jadwal berulang, target, utang, dan " +
                    "komitmen. Cadangan Catatan Keuangan dienkripsi dengan " +
                    "frasa sandi yang kamu pilih. Saat kamu menyimpan atau memulihkan berkas, pemilih berkas Android dan layanan tujuan " +
                    "yang kamu pilih bisa memproses atau menyimpannya sesuai ketentuan dan pemberitahuan privasi mereka. " +
                    "Catatan Keuangan tidak bisa menghapus salinan eksternal itu untukmu.",
            )),
            LegalSection("7. Layanan lainnya", listOf(
                "Penyedia tidak menerima atau menjual salinan online buku besarmu, dan tidak memakainya untuk iklan. " +
                    "Layanan eksternal hanya menerima informasi yang dijelaskan di atas atau berkas yang kamu pilih untuk " +
                    "disimpan. Sistem operasi, toko aplikasi, dan penyedia jaringan bisa memproses " +
                    "informasi teknis sesuai ketentuan mereka. Masukan yang dikirim lewat penyedia email bukan salinan buku besar " +
                    "Catatan Keuangan; hindari menyertakan detail keuangan di dalamnya.",
            )),
            LegalSection("8. Pilihan dan hak privasimu", listOf(
                "Kamu bisa melihat dan memperbaiki catatan di aplikasi, mengekspor buku besarmu dari Pengaturan, dan menghapus data lokal " +
                    "dari Pengaturan. Penghapusan tidak menghapus ekspor atau cadangan yang sudah disimpan di tempat lain. " +
                    "Permintaan kurs hanya terjadi saat kamu mengonversi transaksi mata uang asing atau target komitmen. Pengecekan " +
                    "pembaruan memakai GitHub untuk build sideload dan Google Play untuk build yang dipasang dari Play. Keduanya " +
                    "tidak mengirim catatan. Pengingat opsional memakai pengaturan lokal dan hanya memeriksa catatan lokal. Teks transaksi yang dibagikan " +
                    "atau ditempel diproses di HP ini dan tidak disimpan sebagai pesan.",
                "Hak privasimu bergantung pada hukum yang berlaku di tempat tinggalmu. Hukum itu mungkin memberimu hak untuk " +
                    "meminta akses, koreksi, atau penghapusan, menolak pemrosesan tertentu, atau mengajukan keluhan ke " +
                    "otoritas perlindungan data. Kamu bisa mengelola catatan yang hanya tersimpan di HP ini lewat aplikasi. Untuk " +
                    "permintaan tentang informasi yang ditangani penyedia, email $PRIVACY_CONTACT. Jangan kirim detail catatan " +
                    "kecuali diperlukan untuk menangani permintaanmu.",
            )),
            LegalSection("9. Anak-anak", listOf(
                "Catatan Keuangan tidak dirancang untuk mengumpulkan informasi dari anak-anak. Siapa pun yang belum cukup umur " +
                    "untuk bertindak secara hukum hanya boleh memakainya dengan izin orang tua atau wali hukum.",
            )),
            LegalSection("10. Perubahan", listOf(
                "Jika Pemberitahuan ini berubah secara material, aplikasi akan menampilkannya dan meminta kamu menyetujui " +
                    "dokumen baru sebelum lanjut. Kamu bisa membaca Syarat dan Pemberitahuan ini dari " +
                    "Pengaturan kapan saja. Hubungi $PRIVACY_CONTACT untuk pertanyaan privasi.",
            )),
        ),
    )

    fun isCurrentAcceptance(termsVersion: String?, privacyVersion: String?): Boolean =
        termsVersion == TERMS_VERSION && privacyVersion == PRIVACY_VERSION
}
