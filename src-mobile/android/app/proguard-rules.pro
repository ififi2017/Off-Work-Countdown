# Room 2.6.1 arrives through WorkManager and creates generated databases by reflection.
# Its consumer rule preserves the class but not the no-arg constructor in R8 full mode.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
