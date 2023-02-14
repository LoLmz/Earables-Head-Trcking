# Erables-Head-Trcking

## Dataset:

Data Structure:
Folder:
	- Name indicate degrees of rotations around y axes (yaw)

File Name:
	Indicate direction (left or right), deegrees of rotation and kind of movement (static or dynamic).
		- Static means that the subject remain at fixed position, for example fixed at 30°
		- Dynamic means that the subject continusly rotate, for example from 0° to 30°

File Structure:
	- time: timestamp
	- accX, accY, accZ: Accelerometer values in acceleration in g
	- gyrX, gyrY,gyrZ: Gyroscope values in degrees/second
	- accX_cal, accY_cal, accZ_cal: Accelerometer values in acceleration in g calibrated* 
	- gyrX_cal, gyrY_cal,gyrZ_cal: Gyroscope values in degrees/second calibrated*
	- Roll: calculated combining accelerometer and gyroscope data with Kalman Filter. (It works, but I have not tested the performance)
	- Pitch: calculated combining accelerometer and gyroscope data with Kalman Filter. (It works, but I have not tested the performance)
	- pose: class of pose for classification 
		- Center: between -0.05 and +0.05 degrees
    	- Right-30: between +0.25 and +0.35 degrees
    	- Right-45: between +0.40 and +0.50 degrees
    	- Right-60: between +0.55 and +0.65 degrees
    	- Right-90: between +0.85 and +0.95 degrees
    	- Left-30: between -0.25 and -0.35 degrees
    	- Left-45: between -0.40 and -0.50 degrees
    	- Left-60: between -0.55 and -0.65 degrees
    	- Left-90: between -0.85 and -0.95 degrees
    	- Other: transitions between classes
    - X: rotations around X axis
    - Y: rotations around Y axis (Ground truth for Yaw)

*Calibration phase:
	The technique I use to calibrate the IMU is quite simple and more sophisticated methods exist.
	I collect 200 accelerometer and gyroscope samples while keeping head fix at center position and then take the average of the values for each axis. This gives the offset that has to be applied to each axis in order to have the appropriate readings: gyro X,Y and Z very close to 0 and accelerometer X=1, Y=0 and Z=0 when looking forword.



