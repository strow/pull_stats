function pull_stats_airibrad_hot(year, filter, cfg);

%**************************************************
% need to make this work on daily concat files: look for loop over
% granules, this will need to be removed. Also break out by fov
% (add loop and index over p.ifov)
%
% following the 'file in; file out' standard, this routine will
% read in ONE daily concatenated rtp file and calculate its
% stats. There will be a driver function above this that will feed
% rtp file paths to this routine and can provide for slurm indexing
% and chunking
%**************************************************

addpath /asl/matlib/h4tools
addpath /asl/rtp_prod/airs/utils
addpath /asl/packages/rtp_prod2/util
addpath /home/sergio/MATLABCODE/PLOTTER  %
                                         % equal_area_spherical_bands
addpath /asl/matlib/rtptools  % mmwater_rtp.m

[sID, sTempPath] = genscratchpath();

% check for existence of configuration struct
bCheckConfig = false;
if nargin == 3
    bCheckConfig = true;
end

% record run start datetime in output stats file for tracking
trace.RunDate = datetime('now','TimeZone','local','Format', ...
                         'd-MMM-y HH:mm:ss Z');
trace.Reason = 'Normal pull_stats runs';
if bCheckConfig & isfield(cfg, 'Reason')
    trace.Reason = cfg.Reason;
end

bRunKlayers = true;
klayers_exec = ['/asl/packages/klayersV205/BinV201/' ...
                'klayers_airs_wetwater'];
if bCheckConfig & isfield(cfg, 'klayers') & cfg.klayers == false
    bRunKlayers = false;
end
trace.klayers = bRunKlayers;

trace.droplayers = false;
if bCheckConfig & isfield(cfg, 'droplayers') & cfg.droplayers == true
    trace.droplayers = true;
end

cstr =[ 'bits1-4=NEdT[0.08 0.12 0.15 0.20 0.25 0.30 0.35 0.4 0.5 0.6 0.7' ...
  ' 0.8 1.0 2.0 4.0 nan]; bit5=Aside[0=off,1=on]; bit6=Bside[0=off,1=on];' ...
  ' bits7-8=calflag&calchansummary[0=OK, 1=DCR, 2=moon, 3=other]' ];

basedir = fullfile('/asl/rtp/rtp_airibrad_v5/', ...
                   'hot', int2str(year));
dayfiles = dir(fullfile(basedir, 'era_airibrad_day*_hot.rtp'));
fprintf(1,'>>> numfiles = %d\n', length(dayfiles));

% calculate latitude bins
nbins=20; % gives 2N+1 element array of lat bin boundaries
latbins = equal_area_spherical_bands(nbins);
nlatbins = length(latbins);

iday = 1;
%for giday = 1:10:length(dayfiles)
for giday = 1:length(dayfiles)
   fprintf(1, '>>> year = %d  :: giday = %d\n', year, giday);
   a = dir(fullfile(basedir,dayfiles(giday).name));
   if a.bytes > 100000
      [h,ha,p,pa] = rtpread(fullfile(basedir,dayfiles(giday).name));
      f = h.vchan;  % AIRS proper frequencies
      
      % sanity check on p.robs1 as read in. (There have been
      % instances where this array is short on the spectral
      % dimension which fails in rad2bt. We trap for this here)
      obs = size(p.robs1);
      chans = size(f);
      if obs(1) ~= chans(1)
          fprintf(2, ['**>> ERROR: obs/vchan spectral channel ' ...
                      'mismatch in %s. Bypassing day.\n'], dayfiles(giday).name);
          continue;
      end
            
      switch filter
        case 1
          k = find(p.iudef(4,:) == 68); % descending node (night)
          sDescriptor='_desc';
        case 2
          k = find(p.iudef(4,:) == 68 & p.landfrac == 0); % descending
                                                     % node (night) ocean
          sDescriptor='_desc_ocean';
        case 3
          k = find(p.iudef(4,:) == 68 & p.landfrac == 1); % descending node
                                                        % (night), land
          sDescriptor='_desc_land';
        case 4
          k = find(p.iudef(4,:) == 65); % ascending node (day)
          sDescriptor='_asc';
        case 5
          k = find(p.iudef(4,:) == 65 & p.landfrac == 0); % ascending node
                                                         % (day), ocean
          sDescriptor='_asc_ocean';
        case 6
          k = find(p.iudef(4,:) == 65 & p.landfrac == 1); % ascending node
                                                        % (day), land
          sDescriptor='_asc_land';
      end

      pp = rtp_sub_prof(p, k);
      clear p;
      
      if bRunKlayers
% $$$           % klayers kills previous sarta in the rtp structures so
% $$$           % we need to save values and re-insert after klayers
% $$$           % finishes
% $$$           sarta_rclearcalc = pp.sarta_rclearcalc;
% $$$           tcc = pp.tcc;
% $$$           
          % run klayers on the rtp data to convert levels -> layers
          fprintf(1, '>>> running klayers... ');
          fn_rtp1 = fullfile(sTempPath, ['airs_' sID '_1.rtp']);
          rtpwrite(fn_rtp1, h,ha,pp,pa);
          clear pp;
          fn_rtp2 = fullfile(sTempPath, ['airs_' sID '_2.rtp']);
          klayers_run = [klayers_exec ' fin=' fn_rtp1 ' fout=' fn_rtp2 ...
                         ' > ' sTempPath '/kout.txt'];
          unix(klayers_run);
          fprintf(1, 'Done\n');

          % Read klayers output into local rtp variables
          [h,ha,pp,pa] = rtpread(fn_rtp2);
          
          f = h.vchan;  % AIRS proper frequencies

% $$$           % restore sarta values
% $$$           pp.sarta_rclearcalc = sarta_rclearcalc;
% $$$           pp.tcc = tcc;
% $$$           clear sarta_rclearcalc tcc;
% $$$           
% $$$           % get column water
% $$$           mmwater = mmwater_rtp(h, pp);

          % Check for obs with layer profiles that go lower than
          % topography. Need to check nlevs and NaN out any layers
          % at or below this level

          % ** Any layers-sensitive variables added in averaging code below must
          % ** be checked here first.
          for i=1:length(pp.nlevs)
              badlayers = pp.nlevs(i) : 101;
              pp.plevs(badlayers, i) = NaN;
              pp.palts(badlayers, i) = NaN;
              pp.gas_1(badlayers, i) = NaN;
              pp.gas_2(badlayers, i) = NaN;
              pp.gas_3(badlayers, i) = NaN;
              pp.gas_4(badlayers, i) = NaN;
              pp.gas_5(badlayers, i) = NaN;
              pp.gas_6(badlayers, i) = NaN;
              pp.gas_12(badlayers, i) = NaN;          
              pp.ptemp(badlayers, i) = NaN;
          end
          
          
      end

      % Initialize counts
      [nedt,ab,ical] = calnum_to_data(pp.calflag,cstr);
      n = length(pp.rlat);
      count_all = ones(2378,n);
      for i=1:2378
         % Find bad channels
         k = find( pp.robs1(i,:) == -9999 | ical(i,:) ~= 0 | nedt(i,:) > 1);
%          % These are the good channels
%          kg = setdiff(1:n,k);
% NaN's for bad channels
         pp.robs1(i,k) = NaN;
         pp.rcalc(i,k) = NaN;
         count_all(i,k) = 0;
      end

      % Loop over latitude bins
      for ilat = 1:nlatbins-1
          % subset based on latitude bin
          inbin = find(pp.rlat > latbins(ilat) & pp.rlat <= ...
                       latbins(ilat+1));
          if (length(inbin) == 0)
              continue;   % no obs in current lat bin. go to next
                          % lat bin
          end
          p = rtp_sub_prof(pp,inbin);
          bincount = count_all(:,inbin); 
% $$$           
          % Radiance mean and std
          r  = p.robs1;
% $$$           cldy_calc = p.rcalc;
% $$$           clr_calc = p.sarta_rclearcalc;
          
          % spectral
          robs(iday,ilat,:) = nanmean(r,2);
% $$$           rcldy(iday,ilat,:) = nanmean(cldy_calc,2);
% $$$           rcldybias_std(iday,ilat,:) = nanstd(r-cldy_calc,0,2);
% $$$           rclr(iday,ilat,:) = nanmean(clr_calc,2);
% $$$           rclrbias_std(iday,ilat,:) = nanstd(r-clr_calc,0,2);
          
          lat_mean(iday,ilat) = nanmean(p.rlat);
          lon_mean(iday,ilat) = nanmean(p.rlon);
          solzen_mean(iday,ilat) = nanmean(p.solzen);
          solazi_mean(iday,ilat) = nanmean(p.solazi);
          rtime_mean(iday,ilat)  = nanmean(p.rtime);
          count(iday,ilat,:) = sum(bincount,2)';
          tcc_mean(iday, ilat) = nanmean(p.tcc);
          stemp_mean(iday,ilat) = nanmean(p.stemp);
          ptemp_mean(iday,ilat,:) = nanmean(p.ptemp,2);
          gas1_mean(iday,ilat,:) = nanmean(p.gas_1,2);
          gas3_mean(iday,ilat,:) = nanmean(p.gas_3,2);
          spres_mean(iday,ilat) = nanmean(p.spres);
          nlevs_mean(iday,ilat) = nanmean(p.nlevs);
          iudef4_mean(iday,ilat) = nanmean(p.iudef(4,:));
% $$$           mmwater_mean(iday,ilat) = nanmean(binwater);
          satzen_mean(iday,ilat) = nanmean(p.satzen);
          satazi_mean(iday,ilat) = nanmean(p.satazi);
          plevs_mean(iday,ilat,:) = nanmean(p.plevs,2);
      end  % end loop over latitudes
          iday = iday + 1
   end % if a.bytes > 1000000
end  % giday

% $$$ startdir='/asl/rtp_lustre';
startdir='/home/sbuczko1/WorkingFiles/';
outfile = [startdir 'data/stats/airs/rtp_airibrad_era_rad_kl_' ...
           int2str(year) '_hot' sDescriptor ];
eval_str = ['save ' outfile [' robs *_mean count* latbins ' ...
                    'trace']];
% $$$ eval_str = ['save ' outfile ' robs *_mean count latbins trace'];
eval(eval_str);
