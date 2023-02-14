import pandas as pd

def change_pose(filename):
    df=pd.read_csv(filename)
    df.loc[(df['Y'] >= -0.05) & (df['Y'] <= 0.05), "pose"] = "center"
    # Modifiche right 
    df.loc[(df['Y'] >= 0.25) & (df['Y'] <= 0.35), "pose"] = "right-30"
    df.loc[(df['Y'] >= 0.40) & (df['Y'] <= 0.50), "pose"] = "right-45"
    df.loc[(df['Y'] >= 0.55) & (df['Y'] <= 0.65), "pose"] = "right-60"
    df.loc[(df['Y'] >= 0.85) & (df['Y'] <= 0.95), "pose"] = "right-90"
    # Modifiche left
    df.loc[(df['Y'] <= -0.25) & (df['Y'] >= -0.35), "pose"] = "left-30"
    df.loc[(df['Y'] <= -0.40) & (df['Y'] >= -0.50), "pose"] = "left-45"
    df.loc[(df['Y'] <= -0.55) & (df['Y'] >= -0.65), "pose"] = "left-60"
    df.loc[(df['Y'] <= -0.85) & (df['Y'] >= -0.95), "pose"] = "left-90"
    # caso tra 0.05 e 0.25
    df.loc[(df['Y'] > 0.05) & (df['Y'] < 0.25), "pose"] = "other"
    # caso tra -0.05 e -0.25
    df.loc[(df['Y'] < -0.05) & (df['Y'] > -0.25), "pose"] = "other"

    df.to_csv(filename, index=False)
    print("finish")

if __name__ == "__main__":

    li = ["left_90_dyn_0.csv","right_90_dyn_0.csv","left_90_static_0.csv","left_90_static_1.csv","right_90_static_1.csv","right_90_static_0.csv"]
    for l in li:
        change_pose(l)