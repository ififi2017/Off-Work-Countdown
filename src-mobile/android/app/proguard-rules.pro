# Room 2.6.1 keeps database classes but omits their reflective constructors.
# WorkManager needs this constructor during app startup with R8 strict full mode.
-keepclassmembers class * extends androidx.room.RoomDatabase {
    public <init>();
}
