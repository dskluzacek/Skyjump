package net.skluzacek.skyjump;

import android.app.Activity;
import android.content.pm.ActivityInfo;

import org.libsdl.app.SDLActivity;

public class SkyjumpActivity extends SDLActivity
{
    @Override
    public void setOrientationBis(int w, int h, boolean resizable, String hint)
    {
        mSingleton.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }
}
